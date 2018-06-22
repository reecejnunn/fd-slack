
def user_is_admin?( team_id, user_id )
	logger.debug(__method__){ "Is #{user_id}@#{team_id} an admin of this LaaS instance?" }

	admins = $redis.smembers("laas:config:#{team_id}:admins")
	if admins.nil? || admins == ""
		# No admins, trivially the user is not an admin
		logger.warn(__method__){ "No admins defined for team #{team_id}. laas:config:#{team_id}:admins == '#{admins.inspect}'" }
		return false
	end

	logger.debug(__method__){ "Admins: #{admins.inspect}" }

	return admins.include? user_id
end

def from_slack?( token )
	logger.debug(__method__){ "Checking if Slack token is valid for this team" }
	# i.e. did this request really come from Slack?

	env_token = ENV['SLACK_API_TOKEN']

	if env_token == token
		return true
	else
		logger.error(__method__){ "Invalid token_from_Slack!" }
		return false
	end
end

def slack_message ( text )
	json ({
		"response_type" => "in_channel",
		"text"          => text
	})
end

def slack_message_as! ( text, user, channel )
	case user
	when "techops", "sd", "servicedesk"
		image = "https://cdn1.iconfinder.com/data/icons/user-pictures/100/supportmale-512.png"
	when "slm"
		image = "https://cdn1.iconfinder.com/data/icons/user-pictures/100/female1-512.png"
	when "director"
		image = "https://cdn1.iconfinder.com/data/icons/user-pictures/101/malecostume-512.png"
	when "pagerduty"
		image = "https://slack-files2.s3-us-west-2.amazonaws.com/avatars/2016-06-09/49671169684_cbdc45293ab75ea06413_512.png"
	when "nagios"
		image = "https://a.slack-edge.com/7f1a0/plugins/nagios/assets/service_512.png"
	else
		image = "https://cdn1.iconfinder.com/data/icons/user-pictures/100/male3-512.png"
	end
	print "User: #{user} Image: #{image} Text: #{text}"
	message_text = ERB::Util.url_encode(text)
	username = ERB::Util.url_encode(user.upcase!)
	icon_url = ERB::Util.url_encode(image)

	post_url = "https://slack.com/api/chat.postMessage?" +
		"token=#{ENV['SLACK_API_TOKEN_OTHER']}" +
		"&channel=#{channel}" +
		"&username=#{username}" +
		"&icon_url=#{icon_url}" +
		"&as_user=false" +
		"&text=#{message_text}"

	RestClient.post(post_url)
end

def slack_secret_message ( text )
	json ({
		"text"          => text
	})
end

# Parse a string for slacky things
def slack_parse( team_id, text )

	text = slack_parse_jira( team_id, text )

	text = slack_parse_users( team_id, text )

	text = slack_parse_channels( team_id, text )

	text
end

def slack_parse_jira( team_id, text )
	# JIRA ticket match
	# TODO: ensure this isn't part of another word, by splitting up into words first

	jira_url = $redis.get( "laas:config:#{team_id}:jira_url" )
	if jira_url.nil? || jira_url == ""
		logger.warn(__method__){ "No jira_url defined for team #{team_id}. laas:config:#{team_id}:jira_url == '#{jira_url.inspect}'" }
		jira_url = "https://jira.example.com/"
	end

	logger.debug(__method__){ "Parsing for JIRA tickets" }

	text = text.gsub( /\p{Alpha}+-\p{Digit}+/ , "<#{jira_url}browse/\\0|\\0>" )

	logger.debug(__method__){ "After parsing for JIRA tickets: #{text}" }

	text
end

def slack_parse_channels( team_id, text )
	# Detect #channels
	all_channels = Slack.channels_list["channels"]
	if all_channels.nil?
		logger.warn(__method__){ "Unable to list all Slack channels!" }
		return text
	end

	logger.debug(__method__){ "Parsing for Slack channels" }

	lines = text.split("\n")
	lines.map! do |line|
		words = line.split( " " )
		words.map! do |word|
			# if this does not start with #, it's not a channel
			# so just return it as is
			unless word.start_with?('#')
				word
			else
				# strip # from channel name
				channel_name = word[1..-1]

				# Does the named channel exist?
				channel = all_channels.detect{ |channel| channel["name"] == channel_name }

				# No. Return as plaintext
				if channel.nil?
					word
				else
					# Channels are <#C024BE7LR|general> (general is optional)
					"<##{channel['id']}>"
				end
			end
		end
		words.join(" ")
	end
	text = lines.join( "\n" )

	logger.debug(__method__){ "After parsing for Slack channels: #{text}" }

	text
end

def slack_parse_users( team_id, text )
	# Detect @users
	# TODO: add user groups here too, but can't be done with a test token

	all_users = Slack.users_list["members"]
	if all_users.nil?
		logger.warn(__method__){ "Unable to list all Slack users!" }
		return text
	end

	logger.debug(__method__){ "Parsing for Slack users" }

	lines = text.split("\n")
	lines.map! do |line|
		words = line.split( " " )
		words.map! do |word|
			# if this does not start with @, it's not a user
			# so just return it as is
			unless word.start_with?('@')
				word
			else
				# strip @ from user name
				user_name = word[1..-1]

				# Does the named user exist?
				# i.e. legacy "username"
				user = all_users.detect{ |user| user['name'] == user_name }

				# TODO: check profile.real_name(normalized)? ids? profile.display_name(normalized)? profile.email?

				# No. Return as plaintext
				if user.nil?
					word
				else
					# users are <@U024BE7LH|lucy>
					"<@#{user['id']}>"
				end
			end
		end
		words.join(" ")
	end
	text = lines.join( "\n" )

	logger.debug(__method__){ "After parsing for Slack users: #{text}" }

	text
end










