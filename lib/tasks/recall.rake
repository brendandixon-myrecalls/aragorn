namespace :recalls do

  def data_only(h)
    h = h.reject{|k, v| ['jsonapi', :jsonapi, 'links', :links, 'meta', :meta].include?(k) }
    h[:data] = h[:data].reject{|k, v| ['links', :links].include?(k) }
    h[:data][:attributes] = h[:data][:attributes].reject{|k, v| ['reviewed', :reviewed, 'state', :state].include?(k) }
    h
  end

  def ensure_indexes
    Dir.glob(Rails.root.join('app', 'models', '*.rb')) do |path|
      model = File.basename(path, '.rb').classify.constantize
      next unless model.respond_to?(:create_indexes)
      model.remove_indexes
      model.create_indexes
      puts "  Ensured indexes for #{model.name}"
    end
  end

  def ensure_default_users(force = false)
    users_config_path = Rails.root.join(ENV['USERS_CONFIG_PATH'] || '.aws/users.json')
    users_config = (JSON.parse(File.read(users_config_path)) rescue {}).with_indifferent_access
    (users_config[Rails.env] || []).each do |attributes|
      u = User.with_email(attributes[:email]).first
      if u.blank? || force
        begin
          if u.present?
            attributes[:id] = u.id
            puts "Destroying #{u.email}"
            User.destroy_with_stripe(u)
          end

          u = User.create!(attributes)
          preference = u.preference

          unless u.acts_as_worker? || Rails.env.production?
            preference.alert_for_vins =
            preference.send_vin_summaries =
            preference.alert_by_email =
            preference.alert_by_phone =
            preference.send_summaries = true
            preference.audience = FeedConstants::DEFAULT_AUDIENCE
            preference.categories = FeedConstants::PUBLIC_CATEGORIES
            preference.distribution = USRegions::REGIONS[:nationwide]
            preference.risk = FeedConstants::RISK
            u.save!

            EmailCoupon.create!(email: u.email, coupon_id: Coupon.free_forever) unless EmailCoupon.coupon_for_email(u.email).present?

            s = StripeHelper.create_subscription(u, Plan.yearly_all, Coupon.free_forever, StripeHelper.create_token)

            # if u.email == 'brendandixon@me.com'
            #   %w(JTDKARFU0H3528314 JTEDC3EH6D2015598).each_with_index do |vin, i|
            #     v = s.vins[i]
            #     v.updated_at = Time.now
            #     v.vin = vin
            #     v.vehicle = Vehicles::Basic.vehicle_from_vin(v.vin)
            #   end

            #   u.save!
            # end

            u.email_confirmed!
            u.phone_confirmed!
          else
            preference.alert_for_vins =
            preference.send_vin_summaries =
            preference.alert_by_email =
            preference.alert_by_phone =
            preference.send_summaries = false
            preference.audience =
            preference.categories =
            preference.distribution =
            preference.risk = nil
            u.save!
          end

          puts "  Ensured #{attributes[:email]}"

        rescue Exception => e
          puts "  ERROR creating #{attributes[:email]} - #{e}"
          u.errors.full_messages.each{|m| puts "  #{m}"}
        end
      else
        puts "  #{attributes[:email]} already exists"
      end
    end
  end

  def jsonize(h)
    h.deep_transform_keys{|k| k.jsonize}
  end

  desc 'Ensure the MongoDB has indexes and users'
  task :ensure, [:force] => [:environment] do |task, args|
    args.with_defaults(force: false)
    ensure_indexes
    ensure_default_users(args.force)
  end

  desc 'Ensure the MongoDB indexes'
  task :indexes, [] => [:environment] do
    ensure_indexes
  end

  desc 'Pull Recalls from S3 into MongoDB'
  task :pull, [:clean,:force] =>  [:environment] do |task, args|
    args.with_defaults(clean: false)

    if args.clean
      puts "Removing all existing recalls"
      Recall.destroy_all
      VehicleRecall.destroy_all
      ensure_indexes
    end

    puts "Loading Recalls from S3 bucket #{AwsHelper::AWS_BUCKET}"
    puts "WARNING: Existing Recalls will be overwritten" if args.force

    File.unlink('conflicts.json') rescue nil
    File.unlink('duplicates.json') rescue nil
    File.unlink('errors.json') rescue nil

    count = 0
    errors = []
    conflicts = []
    duplicates = []
    AwsHelper.recalls.each do |object|
      putc '.'
      begin
        json = JSON.parse(object.get.body.read, symbolize_names: true)
        id = json[:data][:id] || nil
        is_vehicle = json[:data][:type] == 'vehicleRecalls'

        recall = (is_vehicle ? VehicleRecall : Recall).from_json(json)
        recall.id = id if id.present? && args.clean

        prior = (is_vehicle ? VehicleRecall : Recall).where(id: recall.id)
        needs_saving = !prior.exists?

        # Sources may publish a Recall with differing publication dates so
        # take the Recall state from the S3 version with the most advanced state
        if prior.exists?
          prior_recall = prior.first

          # If the incoming Recall is further along, keep it
          if is_vehicle
            duplicates << recall
          else
            if Recall.compare_recall_states(recall.state, prior_recall.state) > 0
              needs_saving = true
              duplicates << prior_recall
              conflicts << {accepted: recall.canonical_name, rejected: prior_recall.canonical_name}
            else
              duplicates << recall
              conflicts << {accepted: prior_recall.canonical_name, rejected: recall.canonical_name}
            end
          end
        end

        if needs_saving
          recall.sanitize!
          recall.save!
          count += 1
        end
      rescue Exception => e
        puts
        puts "ERROR: Unable to load #{object.key} -- #{e}"
        errors << recall
      end
    end
    puts

    puts "Loaded #{count} files -- #{duplicates.length} Existed, #{errors.length} Errors"
    if conflicts.present?
      File.write('conflicts.json', conflicts.to_json)
      puts "Wrote conflicts to 'conflicts.json'"
    end

    if duplicates.present?
      File.write('duplicates.json', duplicates.to_json)
      puts "Wrote duplicate Recalls to 'duplicates.json'"
    end

    if errors.present?
      File.write('errors.json', errors.to_json)
      puts "Wrote error Recalls to 'errors.json'"
    end
  end

  desc 'Push Recalls from MongoDB to S3'
  task :push, [:force] => [:environment] do |task,args|
    raise "This task can be used only in the production environment" unless Rails.env.production?

    puts "Pushing #{Recall.count + VehicleRecall.count} recalls from MongoDB to S3 bucket #{AwsHelper::AWS_BUCKET}"
    args.with_defaults(force: false)

    puts "WARNING: Recalls and VehicleRecalls will be overwritten" if args.force

    count = 0
    errors = 0
    existing = 0

    puts "  Pushing Recalls..."
    Recall.all.each do |recall|
      putc '.'
      count += 1
      if !args.force && AwsHelper.recall_exists?(recall)
        existing += 1
      elsif !AwsHelper.upload_recall(recall)
        errors += 1
      end
    end
    puts

    puts "  Pushing VehicleRecalls..."
    VehicleRecall.all.each do |recall|
      putc '.'
      count += 1
      if !args.force && AwsHelper.recall_exists?(recall)
        existing += 1
      elsif !AwsHelper.upload_recall(recall)
        errors += 1
      end
    end
    puts

    puts "Pushed #{count} files -- #{existing} Existed, #{errors} Errors"
  end

  desc 'Reset Recall JSON used in specs to match latest Recalls'
  task :reset, [] => [:environment] do
    data_dir = Rails.root.join('spec', 'data')
    puts "Reseting JSON in #{data_dir}"
    Dir['*.json', base: data_dir].each do |fn|
      file_path = File.join(data_dir, fn)
      r = Recall.from_path(file_path)
      r.sanitize!
      File.write(file_path, data_only(r.as_json).to_json)
      putc '.'
    end
    puts
  end

  desc 'Create data for use in development'
  task :prime, [:clean, :count_users] => [:environment] do |task, args|
    raise "This task can be used only in the development environment" unless Rails.env.development?

    args.with_defaults(clean: false, count_users: 0, count_recalls: 0)

    require 'factory_bot_rails'
    include FactoryBot::Syntax::Methods

    st = Time.now

    if args.clean
      puts "Removing all existing data"
      ::Mongoid::Clients.default.database.drop
    end
    
    puts 'Ensuring indexes'
    ensure_indexes

    puts 'Ensuring default users'
    ensure_default_users
    User.with_email('admin@nomail.com').first.refresh_access_token!(5.years.from_now)
    User.with_email('worker@nomail.com').first.refresh_access_token!(5.years.from_now)

    puts "Creating #{args.count_users} member Users"
    args.count_users.to_i.times do |i|
      create(:user)
      putc '.' if i % 10
    end
    puts

    d = (Time.now - st).to_i
    m = d / 60
    s = d % 60

    puts "Created #{args.count_users} Users and #{args.count_recalls} Recalls in #{'%02d' % m}:#{'%02d' % s}"
  end

  desc 'Ensure all registered VINs have their recalls'
  task :vrecalls, [] => [:environment] do |task, args|
    User.has_vehicle_subscription.each do |u|
      puts "Retrieving VINs and VehicleRecalls for #{u.email}"
      u.vins.each do |vin|
        next if vin.reviewed
        puts "  VIN #{vin.vin}"
        VehicleRecall.ensure_vin_recalls(vin.vin)
        vin.reviewed = true
      end
      u.save!
    end
  end

  desc 'Add route comments to routes.rb'
  task :routes, [] => [:environment] do
    # Rake::Task['routes'].invoke
    # Rake.application['routes'].invoke
    hdr = ["# == Route Map\n"] + `rails routes`.split("\n").map{|l| "# #{l}\n"}
    fn = Rails.root.join('config', 'routes.rb')
    lines = File.readlines(fn).drop_while{|l| l.starts_with?('#')}
    File.write(fn, (hdr+lines).join)
  end

  desc 'Emit geographic distribution statistics'
  task :geostats, [] => [:environment] do
    stats = USRegions::ALL_STATES.inject({}){|o,s| o[s] = 0; o }
    Recall.all.each do |r|
      r.distribution.each{|s| stats[s] += 1}
    end
    puts 'State Distribution'
    stats.each do |k,v|
      puts "#{k} = #{v}"
    end
  end

  desc 'Emit basic statistics on recalls'
  task :pubstats, [:after, :before] => [:environment] do |task, args|
    args.with_defaults(after: '2018-09-01')
    args.with_defaults(before: Time.now)

    after = args.after
    after = after.to_time if after.is_a?(String)
    after = after.beginning_of_day

    before = args.before
    before = before.to_time if before.is_a?(String)
    before = before.end_of_day

    days = ((before - after) / 1.day).round

    categories = {}
    risk = {}
    Recall.published_during(after, before).each do |r|
      next if r.unreviewed?
      next unless (FeedConstants::PUBLIC_CATEGORIES & r.categories).present?
      next unless r.audience.include?('consumers')
      next unless FeedConstants::ALERTED_RISK.include?(r.risk)
      r.categories.each do |c|
        USRegions::REGIONS.keys.each do |region|
          categories[region] = {} unless categories[region].present?
          rc = categories[region]
          rc[c] = (rc[c] || 0) + 1 if (USRegions::REGIONS[region] & r.distribution).present?
        end
      end
      risk[r.risk] = (risk[r.risk] || 0) + 1
    end

    categories.keys.sort.each do |region|
      puts region.to_s.humanize
      t = 0
      categories[region].keys.sort.each do |c|
        v = categories[region][c]
        t += v
        puts "%14s - Total %3d, Monthly %5.1d" % [c.to_s.humanize, v, (v.to_f * 30 / days)]
      end
      puts "%17sTotal %3d, Monthly %5.1d" % [' ', t, (t.to_f * 30 / days)]
      puts
    end
    puts "Risk: #{risk.inspect}"
  end

  desc 'Emit statistics on Recalls'
  task :stats, [] => [:environment] do
    total = 0

    title_length = 0
    max_title = -1
    min_title = 100000

    description_length = 0
    max_description = -1
    min_description = 100000

    max_allergens = 0
    max_categories = 0
    max_contaminants = 0

    count_by_allergen = FeedConstants::FOOD_ALLERGENS.inject({}){|o, a| o[a] = 0; o}
    count_by_category = FeedConstants::ALL_CATEGORIES.inject({}){|o, c| o[c] = 0; o}
    count_by_contaminant = FeedConstants::ALL_CONTAMINANTS.inject({}){|o, c| o[c] = 0; o}
    count_by_name = FeedConstants::NAMES.inject({}){|o, n| o[n] = 0; o}
    count_by_risk = FeedConstants::RISK.inject({}){|o, r| o[r] = 0; o}

    Recall.all.each do |r|
      next if r.unreviewed?

      total += 1
      putc '.' if (total % 10) == 0

      title_length += r.title.length
      max_title = r.title.length if r.title.length > max_title
      min_title = r.title.length if r.title.length < min_title

      description_length += r.description.length
      max_description = r.description.length if r.description.length > max_description
      min_description = r.description.length if r.description.length < min_description

      r.allergens.each do |a|
        count_by_allergen[a] += 1
      end

      max_allergens = r.allergens.length if r.allergens.length > max_allergens
      max_categories = r.categories.length if r.categories.length > max_categories
      max_contaminants = r.contaminants.length if r.contaminants.length > max_contaminants

      r.categories.each do |c|
        count_by_category[c] += 1
      end

      r.contaminants.each do |c|
        count_by_contaminant[c] += 1
      end

      count_by_name[r.feed_name] += 1
      count_by_risk[r.risk] += 1
    end

    title_length = title_length / total
    description_length = description_length / total

    puts
    puts "Recall Statistics"
    puts "  Total                     : #{total}"
    puts "  Average Title Length      : #{title_length}"
    puts "    Maximum #{max_title}"
    puts "    Minimum #{min_title}"
    puts "  Average Description Length: #{description_length}"
    puts "    Maximum #{max_description}"
    puts "    Minimum #{min_description}"
    puts "  Maximum Categories Per    : #{max_categories}"
    count_by_category.each do |k,v|
      puts "    #{k} #{v}"
    end
    puts "  Maximum Allergens Per     : #{max_allergens}"
    count_by_allergen.each do |k,v|
      puts "    #{k} #{v}"
    end
    puts "  Maximum Contaminants Per  : #{max_contaminants}"
    count_by_contaminant.each do |k,v|
      puts "    #{k} #{v}"
    end
    puts "  Feed Name"
    count_by_name.each do |k,v|
      puts "    #{k} #{v}"
    end
    puts "  Risk"
    count_by_risk.each do |k,v|
      puts "    #{k} #{v}"
    end
  end

  desc 'Emit Recall status counts'
  task :status, [] => [:environment] do
    puts "Recalls"
    puts "  Needs Review : #{Recall.needs_review.count}"
    puts "  Needs Sending: #{Recall.needs_sending.count}"
    puts "  Was Sent     : #{Recall.was_sent.count}"
    puts "  Total        : #{Recall.count}"
    puts
    puts "VehicleRecalls"
    puts "  Total        : #{VehicleRecall.count}"
    puts
    puts "Users"
    puts "  Total        : #{User.count}"
  end

  desc 'Locate Recalls with stale links'
  task :stale, [] => [:environment] do
    status = {}
    Recall.all.each do |recall|
      putc '.'
      r = Net::HTTP.get_response((URI(recall.link)))
      next if r.code == '200'

      status[r.code] ||= []
      status[r.code] << recall
    end

    puts
    status.each do |k, v|
      puts "  #{k} had #{v.length} recalls"
    end
    File.write('recall_status.json', status.to_json)

    puts "  Done"
  end

  desc 'Purge faux data'
  task :purge, [:destroy] => [:environment] do |task, args|
    raise "This task can be used only in the development environment" unless Rails.env.development?

    rr = Recall.in_published_order.to_a.map{|r| r.link.starts_with?('http://foo.com') ? r : nil}.compact
    vr = VehicleRecall.in_published_order.where(component: 'The Component').to_a
    us = User.all.to_a.map{|u| u.email.starts_with?('member') ? u : nil}.compact

    puts "Found #{rr.length} Recalls"
    puts "Found #{vr.length} VehicleRecalls"
    puts "Found #{us.length} Users"

    if args.destroy.present?
      puts 'Removing all'
      rr.each{|r| r.destroy}
      vr.each{|v| v.destroy}
      us.each{|u| u.destroy}
    end
  end

end
