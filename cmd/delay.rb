
def delay
	logger.debug "Delayed message test"

	task = Thread.new {
		logger.debug "sleeping for 2 secs"
		sleep(2)
		post_data = slack_secret_message( "Second message" )
		logger.debug "Posting to #{params['response_url']}, #{post_data}"
		RestClient.post(params['response_url'], post_data )
	}

	slack_secret_message "First message"
end
