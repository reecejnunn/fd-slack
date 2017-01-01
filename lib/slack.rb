
def user_is_admin?( team_id, user_id )
	logger.debug "Is #{user_id}@#{team_id} an admin of this LaaS instance?"

	admins = $redis.smembers("laas:config:#{team_id}:admins")
	if admins.nil? || admins == ""
		# No admins, trivially the user is not an admin
		logger.warn "No admins defined for team #{team_id}. laas:config:#{team_id}:admins == '#{admins.inspect}'"
		return false
	end

	logger.debug "Admins: #{admins.inspect}"

	return admins.include? user_id
end

def from_slack?( token )
	# TODO: is token valid?
	# i.e. did this request really come from Slack?

	# Disable for LaaS Develop (in config.ru)
	return true
end


def slack_message ( text )
	json ({
		"response_type" => "in_channel",
		"text"          => text
	})
end

def slack_secret_message ( text )
	json ({
		"text"          => text
	})
end

# Parse a string for slacky things
def slack_parse( text )

	jira_url = ENV['JIRA_URL'] || "https://jira.example.com/"

	# JIRA ticket match
	# TODO: ensure this isn't part of another word
	text = text.gsub( /\p{Alpha}+-\p{Digit}+/ , "<#{jira_url}browse/\\0|\\0>" )

	# Usernames are @bob --> <@bob|bob>
	# TODO: ensure this isn't part of another word or email address or something.
	text = text.gsub( /(@)([a-z0-9][a-z0-9._-]*)/ , "<@\\2|\\2>" )

	# TODO: Detect #channels
	# Channels are <#C024BE7LR|general> (but there must be a way of doing this without knowing the channel id...)

	text
end
