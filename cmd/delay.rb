
def delay

	task = Thread.new {
		sleep(2)
		post_data = slack_message( "Second message" )
		RestClient.post(params['response_url'], post_data )
	}

end
