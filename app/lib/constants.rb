module Constants

  BSON_ID_PATTERN = /([A-Fa-f0-9]{24,24})/
  CAMPAIGN_ID_PATTERN = /([A-Z0-9]{9,9})/
  EMAIL_PATTERN = /\s*[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}\s*/
  FALSE_PATTERN = /f|false|n|no/i
  PASSWORD_PATTERN = /\A(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[\(\)\[\]\{\}\\\/\.,\|\-_~\+=;:<>\?!@#\$%\^&\*])(?=.{8,}).*\z/
  PHONE_PATTERN = /\d{3}\.\d{3}\.\d{4}/
  TRUE_PATTERN = /t|true|y|yes/i

  MAXIMUM_AUTHENTICATION_FAILURES = 5

  MAXIMUM_PAGE_SIZE = 20
  DEFAULT_PAGE_SIZE = MAXIMUM_PAGE_SIZE

  DISTANT_PAST =
  ALWAYS = Time.new(0, 1, 1).end_of_grace_period

  FAR_FUTURE =
  NEVER = Time.new(9999, 12,31).start_of_grace_period

  MINIMUM_RECALL_DATE = Time.new(2018,1,1).beginning_of_day
  MINIMUM_VEHICLE_DATE = Time.new(1970,1,1).beginning_of_day
  MINIMUM_VEHICLE_YEAR = 1970

  LOWERCASE = ('a'..'z').to_a
  UPPERCASE = ('A'..'Z').to_a
  DIGITS = ('0'..'9').to_a
  SPECIAL = %w( ( ) [ ] { } / \ . , | - _ ~ + = ; : < > ? ! @ # $ % ^ & *)
  
  ROLES = %w(admin member worker)

  GUEST_EMAIL = 'guest@nomail.com'
  GUEST_FIRST_NAME = 'Guest'
  GUEST_LAST_NAME = 'Nobody'

end
