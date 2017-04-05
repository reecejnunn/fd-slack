
def populate_all_users
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"

	all_users = $redis.get( all_users_key )
	logger.debug "populate_all_users. all_users (#{all_users_key}) = #{all_users.inspect}"
	if all_users.nil? || all_users == "" || all_users == {}
		channel_info = Slack.channels_info( :channel => params['channel_id'] )

		if channel_info['ok']
			users = channel_info['channel']['members']
		else
			# If channel not found, maybe it's a private channel?
			# https://api.slack.com/methods/groups.info
			channel_info = Slack.groups_info( :channel => params['channel_id'] )

			if channel_info['ok']
				users = channel_info['group']['members']
			else
				fail "No such channel"
			end
		end


		# TODO: REDIS: laas:config:<TEAM_ID>:<CHANNEL_ID>:standup:excluded_users
		$exclude_users = []
		unless ENV['EXCLUDED_STANDUP_USERS'].nil?
			$exclude_users = ENV['EXCLUDED_STANDUP_USERS'].split(",")
		end

		all_users_local = []
		users.each do |uid|
			presence = Slack.users_getPresence( :user => uid )['presence']

			if presence == "active"
				user = Slack.users_info( :user => uid )

				unless $exclude_users.include? user['user']['name']
					all_users_local.push user
				end
			end
		end

		all_users = $redis.get( all_users_key )
		logger.debug "about to set all_users, assuming it's still empty? #{all_users.inspect}"
		if all_users.nil? || all_users == "" || all_users == {}
			logger.debug "For each user in #{all_users_local.inspect}"
			$redis.set( all_users_key, all_users_local.to_json )

			logger.debug "Setting expiry on #{all_users_key} to 30m"
			$redis.expire( all_users_key, 60 * 30 )
		else
			fail "Race condition! Somebody else already started populating the standup!"
		end
	end
end

def standup_participants
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"

	populate_all_users

	all_users = JSON.parse($redis.get( all_users_key ))

	# Extract just the usernames
	all_users.shuffle!

	standup_participants = []
	all_users.each do |user|
		standup_participants.push user['user']
	end

	# Store in DB
	$redis.set( participants_key, standup_participants.to_json )
	$redis.expire( participants_key, 60 * 30 )

	$redis.set( participants_skipped_key, [].to_json )
	$redis.expire( participants_skipped_key, 60 * 30 )

end

def standup
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"

	# TODO: allow slack delayed response for more of this
	case params['text'].chomp
	when "standup next"
		standup_next
	when "standup skip"
		standup_skip
	when "standup", "standup start"
		# TODO: allow user to specify sort orders
		standup_start
	when "standup clear", "standup reset"
		$redis.del( all_users_key )
		slack_secret_message "Reset"
	when "standup done"
		standup_done
	when "standup populate"
		task = Thread.new {
			populate_all_users
			post_data = slack_secret_message "Populated"
			RestClient.post(params['response_url'], post_data )
		}
		slack_secret_message "Populating"
	else
		slack_secret_message "I don't know what to do with: #{params['text'].chomp}"
	end
end

def standup_done
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"
	message = ":boom: Standup Complete! :boom:"

	standup_participants_skipped = JSON.parse($redis.get( participants_skipped_key ))
	unless standup_participants_skipped.empty?
		message = message + "\n\nSkipped users:\n"

		standup_participants_skipped.each do |p|
			pt = "<@#{p['name']}|#{p['name']}> - #{p['real_name']}"
			message = message + "#{pt}\n"
		end
	end

	$redis.del( all_users_key )
	$redis.del( participants_key )
	$redis.del( participants_skipped_key )

	slack_message message
end

def standup_start
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"


	# TODO: all the below should be added to a Slack Message queue

	task = Thread.new {
		post_data = slack_message "`/laas standup start`\n\n<!here>: Standup time!"
		sleep(0.1)
		RestClient.post(params['response_url'], post_data )

		# Get participants of this standup
		logger.debug "getting standup participants"
		standup_participants

		logger.debug "pasting standup participants"
		standup_participants = JSON.parse($redis.get( participants_key ))

		logger.debug "participants: #{standup_participants.inspect}"
		second_response = "Running Order (Shuffled):"
		standup_participants.each do |p|
			logger.debug "participant: #{p.inspect}"
			pt = "<@#{p['name']}|#{p['name']}> - #{p['real_name']}"

			second_response = second_response + "\n#{pt}"
		end

		post_data = slack_message second_response

		# Sleep a second, to ensure first message has been sent
		# This is kinda a hack. Better would be to push messages into a queue, and
		# start a thread to monitor the queue, sending messages as they arrive.
		# Thread would be terminated when the queue contains an EOM item

		sleep(0.1)
		RestClient.post(params['response_url'], post_data )

		post_data = slack_message "Use `/laas standup next` to summon the next person in the list\nUse `/laas standup skip` to skip somebody not present"
		sleep(0.1)
		RestClient.post(params['response_url'], post_data )

		# summon first user
		post_data = standup_next
		sleep(0.1)
		RestClient.post(params['response_url'], post_data )
	}

	slack_message "Initiating Standup"
end

# When did somebody last type /laas standup next?
# TODO: REDIS
$last_standup_next = nil
$last_standup_participant = nil
def standup_next
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"

	# Has nobody called standup_next yet?
	# or has nobody called it in the past 2 seconds?
	# TODO: REDIS
	if $last_standup_next.nil? or ($last_standup_next + 2 < Time.now)
		$last_standup_next = Time.now
	else
		return slack_secret_message "Slow down!\nYou can only run `standup skip` or `standup next` once every two seconds"
	end

	# Is the standup already over?
	standup_participants = JSON.parse($redis.get( participants_key ))
	logger.debug "participants remaining: #{standup_participants.count}"
	if standup_participants.empty?
		return standup_done
	end

	p = standup_participants.shift
	$redis.set( participants_key, standup_participants.to_json )

	# TODO: REDIS
	$last_standup_participant = p
	pt = "<@#{p['name']}|#{p['name']}>"

	up_next = [
		"You're up #{pt}",
		"#{pt}: go go go!",
		"#{pt} your turn",
		"Go go gadget, #{pt}!",
		":partyparrot: summons #{pt}",
		"It's #{pt} O'Clock!",
		"Something something #{pt}",
		"#{pt}!",
		"A wild #{pt} appeared!",
		"#{pt}, would you kindly...",
		":kermit: Today's special guest on the Muppets show: #{pt}",
		":pokeball: I choose you! #{pt}",
		"Achtung #{pt}!",
		"p = Standup.participants.pop(); p['name'] == #{pt}",
		"Is it a bird? Is it a plane? No! It's #{pt}!"
	]

	# Last person
	if standup_participants.empty?
		up_next = [
			"Finally, #{pt}",
			"Lastly, #{pt}",
			"#{pt}, finish us off! :matron:",
			"And for our grand finale, #{pt}!",
			"And last, but by no means least, #{pt}"
		]
	end

	slack_message up_next.sample
end

def standup_skip
	standup_key = "laas:standup:#{params['team_id']}:#{params['channel_id']}"
	all_users_key = "#{standup_key}:all_users"
	participants_key = "#{standup_key}:participants"
	participants_skipped_key = "#{standup_key}:participants_skipped"

	# Has nobody called standup_next yet?
	# or has nobody called it in the past 2 seconds?
	# TODO: REDIS
	if $last_standup_next.nil? or ($last_standup_next + 2 < Time.now)
		# Because we're going to call standup_next afterwards, just unset this
		$last_standup_next = nil
	else
		return slack_secret_message "Slow down!\nYou can only run `standup skip` or `standup next` once every two seconds"
	end

	standup_participants_skipped = JSON.parse($redis.get( participants_skipped_key ))
	standup_participants_skipped.push $last_standup_participant
	$redis.set( participants_skipped_key, standup_participants_skipped.to_json )

	standup_next
end
