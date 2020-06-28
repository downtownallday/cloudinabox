# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-
# functions needed by ssl_certificates.py

from utils import shell, safe_domain_name, sort_domains

def do_web_update(env):
    	# Kick nginx. Since this might be called from the web admin
	# don't do a 'restart'. That would kill the connection before
	# the API returns its response. A 'reload' should be good
	# enough and doesn't break any open connections.
	shell('check_call', ["/usr/sbin/service", "nginx", "reload"])

	#return "web updated\n"
	return ""

def get_web_domains(env, include_www_redirects=True, exclude_dns_elsewhere=True):
	# What domains should we serve HTTP(S) for?
	domains = set()

	# Ensure the PRIMARY_HOSTNAME is in the list
	domains.add(env['PRIMARY_HOSTNAME'])

	# Sort the list so the nginx conf gets written in a stable order.
	domains = sort_domains(domains, env)

	return domains

def get_web_zones(env):
	# What domains should we create DNS zones for? Never create a zone for
	# a domain & a subdomain of that domain.
	domains = get_web_domains(env)

	# Exclude domains that are subdomains of other domains we know. Proceed
	# by looking at shorter domains first.
	zone_domains = set()
	for domain in sorted(domains, key=lambda d : len(d)):
		for d in zone_domains:
			if domain.endswith("." + d):
				# We found a parent domain already in the list.
				break
		else:
			# 'break' did not occur: there is no parent domain.
			zone_domains.add(domain)

	# Make a nice and safe filename for each domain.
	zonefiles = []
	for domain in zone_domains:
		zonefiles.append([domain, safe_domain_name(domain) + ".txt"])

	# Sort the list so that the order is nice and so that nsd.conf has a
	# stable order so we don't rewrite the file & restart the service
	# meaninglessly.
	zone_order = sort_domains([ zone[0] for zone in zonefiles ], env)
	zonefiles.sort(key = lambda zone : zone_order.index(zone[0]) )

	return zonefiles
