# -*- indent-tabs-mode: t; tab-width: 4; -*-
#	
# litmus test for nextcloud


test_home_page() {
	# Browsing to the home page should return a 200 http status.
	#
	# When mariadb is not functioning correctly, the server will
    # return a 500 http status.
	#
	# This also ensures PRIMARY_HOSTNAME is the common name of the
	# server's ssl certificate.
	#
	test_start "home_page"

    local code http_code output
	local url="https://$PRIMARY_HOSTNAME"
	record "[Access $url]"
    output=$(curl -s -L -w "%{http_code}" "$url" 2>>$TEST_OF)
    code=$?
	record "curl returned code: $code"
	record "curl output: $output"
    if [ $code -ne 0 ]; then
        test_failure "Could not access Nextcloud home page, curl returned error $code"
	else
		http_code=$(tail -1 <<<"$output")
		record "got HTTP status=$http_code"
		if [ "$http_code" != "200" ]; then
			test_failure "Retrieving Nextcloud home page returned HTTP status $http_code"
		fi
	fi
    
	test_end
}


suite_start "nextcloud-basic"

test_home_page

suite_end
