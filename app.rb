before do
	# Based on http://stackoverflow.com/a/26675418
	unless ( request.secure? || Sinatra::Application.environment != :production )
		redirect request.url.sub('http', 'https')
	end
end

get '/' do
	"Yo"
end

get '/slack-slash' do
	"Yo. You probably meant to POST to this URL, right?"
end

post '/slack-slash' do
	logger.debug(__method__){ "New request: #{params.inspect}" }

	unless from_slack?( params['token'] )
		return slack_secret_message "Doesn't look like you're calling the API from Slack, buddy!"
	end

	begin
		case params['text'].split.first
		when "", nil
			what_is_fd
		when "wakeup"
			slack_secret_message "OK! I'm up :zzz:"
		when "help"
			slack_secret_message help
		when "start"
			task = Thread.new {
				post_data = slack_message( "Firedrill *start*" )
				RestClient.post(params['response_url'], post_data )
			}
		when "stop"
			task = Thread.new {
				post_data = slack_message( "Firedrill *stop*" )
				RestClient.post(params['response_url'], post_data )
			}
		when "say"
			user = "#{params['text'].split[1]}"
			message_text = "#{params['text'].split[2..-1].join(' ')}"
			slack_message_as!( message_text, user, params['channel_id'] )
		when "help"
			def help
					[
"`/fd wakeup`"
"This wakes up the bot if it's been unused for a while (other wise initial commands may time out and look not pretty)"
""
"`/fd start`"
"Prints Firedrill *start*"
""
"`/fd stop`"
"Prints Firedrill *stop*"
""
"`/fd say`"
"Prints out a message from whichever role you want. Roles with custom profile pictures are slm, techops|sd|servicedesk, director, nagios, and pagerduty|pd. Any other role will use a generic picture."
""
"e.g. `/fd say techops there has been a major multi-blade failure in GUEA :scream:`"
"e.g. `/fd say director Oi <@oliver>! Get some proper work done :shakefist:`"
""
"One word only for the role please otherwise it will use the second word of your role as the first word of your message"
""
"e.g. `/fd say random dev I am online` would show as 'RANDOM' saying 'dev I am online'"
					].join("\n")
			end
			slack_secret_message help
		else
			slack_secret_message "I don't know what to do with: #{params['text'].split.first}"
		end
	rescue Exception => e
		logger.error(__method__){ e.message + "\n" + e.backtrace.join("\n") }
		if user_is_admin?( params['team_id'], params['user_id'] )
			slack_secret_message "Error!\n\n\`\`\`" + e.backtrace.join("\n") + "\n\`\`\`"
		else
			slack_secret_message "Error!\n" + e.message
		end
	end

end
