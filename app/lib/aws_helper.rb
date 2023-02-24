class AwsHelper

  AWS_BUCKET = 'my-recalls'
  AWS_FEEDS_FOLDER = 'feeds'
  AWS_RECALLS_FOLDER = 'recalls'

  class<<self

    # ---------------------------------------------------------------------
    # -                                                                   -
    # - STUB ALL REQUEST RESPONSES IN TEST MODE, see spec/rails_helper.rb -
    # -                                                                   -
    # ---------------------------------------------------------------------

    def invoke(name, **args)
      active_instance.invoke(name, **args)
    end

    def key_for(recall)
      "#{AWS_RECALLS_FOLDER}/#{recall.canonical_name}"
    end

    def recalls
      # Note:
      # - Extend the prefix to include the folder and beginning of the timestamp to it finds the Recalls
      #   and not just the folder
      active_instance.bucket.objects(prefix: "#{AwsHelper::AWS_RECALLS_FOLDER}/2")
    end

    def recall_exists?(recall)
      active_instance.recall_exists?(recall)
    end

    def remove_recall(recall, force=false)
      active_instance.remove_recall(recall, force)
    end

    def upload_recall(recall, force=false)
      active_instance.upload_recall(recall, force)
    end

    protected

      def active_instance
        @@active_instance ||= begin
          config_path = Rails.root.join(ENV['AWS_CONFIG_PATH'] || '.aws/worker.json')
          config = (JSON.parse(File.read(config_path)) rescue {}).with_indifferent_access
          access_key_id = config[:accessKeyId] || ENV['AWS_ACCESS_KEY_ID']
          secret_access_key = config[:secretAccessKey] || ENV['AWS_SECRET_ACCESS_KEY']
          region = config[:region] || ENV['AWS_REGION']

          self.new(access_key_id, secret_access_key, region)
        end
      end

  end

  def bucket
    @bucket ||= Aws::S3::Bucket.new(AWS_BUCKET, client: self.s3)
  end

  def lamb
    @lamb ||= begin
      lamb = Aws::Lambda::Client.new(credentials: @credentials, region: @region)
      if Rails.env.test?
        lamb.stub_responses(:invoke, { executed_version: 'latest', function_error: '', log_result: '', payload: '', status_code: 200 })
      end
      lamb
    end
  end

  def s3
    @s3 ||= begin
      s3 = Aws::S3::Client.new(credentials: @credentials, region: @region)
      if Rails.env.test?
        s3.stub_responses(:delete_object)
        s3.stub_responses(:head_object)
        s3.stub_responses(:put_object, { etag: '"QQTHwGueYtC3qyrkn6v8A"', version_id: 'QQTHwGueYtC3qyrkn6v8A' })
      end
      s3
    end
  end

  def invoke(name, **args)
    params = {
      function_name: name,
      invocation_type: 'RequestResponse',
      log_type: 'None',
    }
    params[:payload] = args.to_json if args.present?

    response = lamb.invoke(params)
    raise Exception.new("Function return #{reponse.status_code} #{response.payload}") unless (200...300).include?(response.status_code)

    logger.debug("Successfully invoked Lambda function #{name}#latest")
    true

  rescue Exception => e
    logger.error("Failed to invoke Lambda function #{name}#latest: #{e}")
    false
  end

  def recall_exists?(recall)
    response = self.s3.head_object(
        bucket: AWS_BUCKET,
        key: AwsHelper.key_for(recall)
    )
    true
  rescue Exception => e
    logger.debug("Recall #{recall.canonical_id} does not exist in bucket: #{e}")
    false
  end

  def remove_recall(recall, force=false)
    if !force && Rails.env.development?
      logger.warn("Rails environment #{Rails.env} is not authorized to remove #{recall.canonical_name}")
      return true
    end

    response = self.s3.delete_object(
      bucket: AWS_BUCKET,
      key: AwsHelper.key_for(recall)
    )
    true
  rescue Exception => e
    logger.error("Failed to remove Recall #{recall.canonical_id} from bucket: #{e}")
    false
  end

  def upload_recall(recall, force=false)
    if !force && Rails.env.development?
      logger.warn("Rails environment #{Rails.env} is not authorized to upload #{recall.canonical_name}")
      return true
    end

    response = self.s3.put_object(
      body: recall.to_json(exclude_self_link: true),
      bucket: AWS_BUCKET,
      key: AwsHelper.key_for(recall)
    )
    true
  rescue Exception => e
    logger.error("Failed to upload Recall #{recall.canonical_id} to bucket: #{e}")
    false
  end

  protected

    def initialize(access_key_id, secret_access_key, region)
      @credentials = Aws::Credentials.new(access_key_id, secret_access_key)
      @region = region
    end

    def logger
      @logger ||= Rails.logger
    end

end
