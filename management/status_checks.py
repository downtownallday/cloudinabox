# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-
import sys, os, os.path, re, subprocess, datetime, multiprocessing.pool

import dns.reversename, dns.resolver
import dateutil.parser, dateutil.tz
import idna
import psutil

#from dns_update import get_dns_zones, build_tlsa_record, get_custom_dns_config, get_secondary_dns, get_custom_dns_records
#from web_update import get_web_domains, get_domains_with_a_records
from ssl_certificates import get_ssl_certificates, get_domain_ssl_files, check_certificate
#from mailconfig import get_mail_domains, get_mail_aliases

from utils import shell, sort_domains, load_env_vars_from_file, load_settings


class FileOutput:
	def __init__(self, buf, width):
		self.buf = buf
		self.width = width

	def add_heading(self, heading):
		print(file=self.buf)
		print(heading, file=self.buf)
		print("=" * len(heading), file=self.buf)

	def print_ok(self, message):
		self.print_block(message, first_line="✓  ")

	def print_error(self, message):
		self.print_block(message, first_line="✖  ")

	def print_warning(self, message):
		self.print_block(message, first_line="?  ")

	def print_block(self, message, first_line="   "):
		print(first_line, end='', file=self.buf)
		message = re.sub("\n\s*", " ", message)
		words = re.split("(\s+)", message)
		linelen = 0
		for w in words:
			if self.width and (linelen + len(w) > self.width-1-len(first_line)):
				print(file=self.buf)
				print("   ", end="", file=self.buf)
				linelen = 0
			if linelen == 0 and w.strip() == "": continue
			print(w, end="", file=self.buf)
			linelen += len(w)
		print(file=self.buf)

	def print_line(self, message, monospace=False):
		for line in message.split("\n"):
			self.print_block(line)
                        
class ConsoleOutput(FileOutput):
	def __init__(self):
		self.buf = sys.stdout

		# Do nice line-wrapping according to the size of the terminal.
		# The 'stty' program queries standard input for terminal information.
		if sys.stdin.isatty():
			try:
				self.width = int(shell('check_output', ['stty', 'size']).split()[1])
			except:
				self.width = 76

		else:
			# However if standard input is not a terminal, we would get
			# "stty: standard input: Inappropriate ioctl for device". So
			# we test with sys.stdin.isatty first, and if it is not a
			# terminal don't do any line wrapping. When this script is
			# run from cron, or if stdin has been redirected, this happens.
			self.width = None

class BufferedOutput:
	# Record all of the instance method calls so we can play them back later.
	def __init__(self, with_lines=None):
		self.buf = [] if not with_lines else with_lines
	def __getattr__(self, attr):
		if attr not in ("add_heading", "print_ok", "print_error", "print_warning", "print_block", "print_line"):
			raise AttributeError
		# Return a function that just records the call & arguments to our buffer.
		def w(*args, **kwargs):
			self.buf.append((attr, args, kwargs))
		return w
	def playback(self, output):
		for attr, args, kwargs in self.buf:
			getattr(output, attr)(*args, **kwargs)

                        
def query_dns(qname, rtype, nxdomain='[Not Set]', at=None):
	# Make the qname absolute by appending a period. Without this, dns.resolver.query
	# will fall back a failed lookup to a second query with this machine's hostname
	# appended. This has been causing some false-positive Spamhaus reports. The
	# reverse DNS lookup will pass a dns.name.Name instance which is already
	# absolute so we should not modify that.
	if isinstance(qname, str):
		qname += "."

	# Use the default nameservers (as defined by the system, which is our locally
	# running bind server), or if the 'at' argument is specified, use that host
	# as the nameserver.
	resolver = dns.resolver.get_default_resolver()
	if at:
		resolver = dns.resolver.Resolver()
		resolver.nameservers = [at]

	# Set a timeout so that a non-responsive server doesn't hold us back.
	resolver.timeout = 5

	# Do the query.
	try:
		response = resolver.resolve(qname, rtype)
	except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
		# Host did not have an answer for this query; not sure what the
		# difference is between the two exceptions.
		return nxdomain
	except dns.exception.Timeout:
		return "[timeout]"

	# Normalize IP addresses. IP address --- especially IPv6 addresses --- can
	# be expressed in equivalent string forms. Canonicalize the form before
	# returning them. The caller should normalize any IP addresses the result
	# of this method is compared with.
	if rtype in ("A", "AAAA"):
		response = [normalize_ip(str(r)) for r in response]

	# There may be multiple answers; concatenate the response. Remove trailing
	# periods from responses since that's how qnames are encoded in DNS but is
	# confusing for us. The order of the answers doesn't matter, so sort so we
	# can compare to a well known order.
	return "; ".join(sorted(str(r).rstrip('.') for r in response))

    
def normalize_ip(ip):
	# Use ipaddress module to normalize the IPv6 notation and
	# ensure we are matching IPv6 addresses written in different
	# representations according to rfc5952.
	import ipaddress
	try:
		return str(ipaddress.ip_address(ip))
	except:
		return ip



def get_services():
	return [
		{ "name": "Local DNS (bind9)", "port": 53, "public": False, },
		#{ "name": "NSD Control", "port": 8952, "public": False, },
		{ "name": "Local DNS Control (bind9/rndc)", "port": 953, "public": False, },
		{ "name": "SSH Login (ssh)", "port": get_ssh_port(), "public": True, },
		{ "name": "HTTP Web (nginx)", "port": 80, "public": True, },
		{ "name": "HTTPS Web (nginx)", "port": 443, "public": True, },
	]



def check_ufw(env, output):
	if not os.path.isfile('/usr/sbin/ufw'):
		output.print_warning("""The ufw program was not installed. If your system is able to run iptables, rerun the setup.""")
		return

	code, ufw = shell('check_output', ['ufw', 'status'], trap=True)

	if code != 0:
		# The command failed, it's safe to say the firewall is disabled
		output.print_warning("""The firewall is not working on this machine. An error was received
					while trying to check the firewall. To investigate run 'sudo ufw status'.""")
		return

	ufw = ufw.splitlines()
	if ufw[0] == "Status: active":
		not_allowed_ports = 0
		for service in get_services():
			if service["public"] and not is_port_allowed(ufw, service["port"]):
				not_allowed_ports += 1
				output.print_error("Port %s (%s) should be allowed in the firewall, please re-run the setup." % (service["port"], service["name"]))

		if not_allowed_ports == 0:
			output.print_ok("Firewall is active.")
	else:
		output.print_warning("""The firewall is disabled on this machine. This might be because the system
			is protected by an external firewall. We can't protect the system against bruteforce attacks
			without the local firewall active. Connect to the system via ssh and try to run: ufw enable.""")

def is_port_allowed(ufw, port):
	return any(re.match(str(port) +"[/ \t].*", item) for item in ufw)



def check_ssh_password(env, output):
	# Check that SSH login with password is disabled. The openssh-server
	# package may not be installed so check that before trying to access
	# the configuration file.
	if not os.path.exists("/etc/ssh/sshd_config"):
		return
	sshd = open("/etc/ssh/sshd_config").read()
	if re.search("\nPasswordAuthentication\s+yes", sshd) \
		or not re.search("\nPasswordAuthentication\s+no", sshd):
		output.print_error("""The SSH server on this machine permits password-based login. A more secure
			way to log in is using a public key. Add your SSH public key to $HOME/.ssh/authorized_keys, check
			that you can log in without a password, set the option 'PasswordAuthentication no' in
			/etc/ssh/sshd_config, and then restart the openssh via 'sudo service ssh restart'.""")
	else:
		output.print_ok("SSH disallows password-based login.")

_apt_updates = None
def list_apt_updates(apt_update=True):
	# See if we have this information cached recently.
	# Keep the information for 8 hours.
	global _apt_updates
	if _apt_updates is not None and _apt_updates[0] > datetime.datetime.now() - datetime.timedelta(hours=8):
		return _apt_updates[1]

	# Run apt-get update to refresh package list. This should be running daily
	# anyway, so on the status checks page don't do this because it is slow.
	if apt_update:
		shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])

	# Run apt-get upgrade in simulate mode to get a list of what
	# it would do.
	simulated_install = shell("check_output", ["/usr/bin/apt-get", "-qq", "-s", "upgrade"])
	pkgs = []
	for line in simulated_install.split('\n'):
		if line.strip() == "":
			continue
		if re.match(r'^Conf .*', line):
			 # remove these lines, not informative
			continue
		m = re.match(r'^Inst (.*) \[(.*)\] \((\S*)', line)
		if m:
			pkgs.append({ "package": m.group(1), "version": m.group(3), "current_version": m.group(2) })
		else:
			pkgs.append({ "package": "[" + line + "]", "version": "", "current_version": "" })

	# Cache for future requests.
	_apt_updates = (datetime.datetime.now(), pkgs)

	return pkgs

def is_reboot_needed_due_to_package_installation():
	return os.path.exists("/var/run/reboot-required")

def check_software_updates(env, output):
	# Check for any software package updates.
	pkgs = list_apt_updates(apt_update=False)
	if is_reboot_needed_due_to_package_installation():
		output.print_error("System updates have been installed and a reboot of the machine is required.")
	elif len(pkgs) == 0:
		output.print_ok("System software is up to date.")
	else:
		output.print_error("There are %d software packages that can be updated." % len(pkgs))
		for p in pkgs:
			output.print_line("%s (%s)" % (p["package"], p["version"]))


def check_free_disk_space(rounded_values, env, output):
	# Check free disk space.
	st = os.statvfs(env['STORAGE_ROOT'])
	bytes_total = st.f_blocks * st.f_frsize
	bytes_free = st.f_bavail * st.f_frsize
	disk_msg = "The disk has %.2f GB space remaining." % (bytes_free/1024.0/1024.0/1024.0)
	if bytes_free > .3 * bytes_total:
		if rounded_values: disk_msg = "The disk has more than 30% free space."
		output.print_ok(disk_msg)
	elif bytes_free > .15 * bytes_total:
		if rounded_values: disk_msg = "The disk has less than 30% free space."
		output.print_warning(disk_msg)
	else:
		if rounded_values: disk_msg = "The disk has less than 15% free space."
		output.print_error(disk_msg)

def check_free_memory(rounded_values, env, output):
	# Check free memory.
	percent_free = 100 - psutil.virtual_memory().percent
	memory_msg = "System memory is %s%% free." % str(round(percent_free))
	if percent_free >= 20:
		if rounded_values: memory_msg = "System free memory is at least 20%."
		output.print_ok(memory_msg)
	elif percent_free >= 10:
		if rounded_values: memory_msg = "System free memory is below 20%."
		output.print_warning(memory_msg)
	else:
		if rounded_values: memory_msg = "System free memory is below 10%."
		output.print_error(memory_msg)



def get_ssh_port():
	# Returns ssh port
	try:
		output = subprocess.check_output(
			[ '/usr/sbin/sshd', '-T' ],
			stderr=subprocess.DEVNULL  # drop warnings (eg, deprecated option)
		).decode('utf-8')
	except FileNotFoundError:
		# sshd is not installed. That's ok.
		return None

	returnNext = False
	for e in output.split():
		if returnNext:
			return int(e)
		if e == "port":
			returnNext = True

	# Did not find port!
	return None


def check_service(i, service, env):
	if not service["port"]:
		# Skip check (no port, e.g. no sshd).
		return (i, None, None, None)

	output = BufferedOutput()
	running = False
	fatal = False

	# Helper function to make a connection to the service, since we try
	# up to three ways (localhost, IPv4 address, IPv6 address).
	def try_connect(ip):
		# Connect to the given IP address on the service's port with a one-second timeout.
		import socket
		s = socket.socket(socket.AF_INET if ":" not in ip else socket.AF_INET6, socket.SOCK_STREAM)
		s.settimeout(1)
		try:
			s.connect((ip, service["port"]))
			return True
		except OSError as e:
			# timed out or some other odd error
			return False
		finally:
			s.close()

	if service["public"]:
		# Service should be publicly accessible.
		if try_connect(env["PUBLIC_IP"]):
			# IPv4 ok.
			if not env.get("PUBLIC_IPV6") or service.get("ipv6") is False or try_connect(env["PUBLIC_IPV6"]):
				# No IPv6, or service isn't meant to run on IPv6, or IPv6 is good.
				running = True

			# IPv4 ok but IPv6 failed. Try the PRIVATE_IPV6 address to see if the service is bound to the interface.
			elif service["port"] != 53 and try_connect(env["PRIVATE_IPV6"]):
				output.print_error("%s is running (and available over IPv4 and the local IPv6 address), but it is not publicly accessible at %s:%d." % (service['name'], env['PUBLIC_IP'], service['port']))
			else:
				output.print_error("%s is running and available over IPv4 but is not accessible over IPv6 at %s port %d." % (service['name'], env['PUBLIC_IPV6'], service['port']))

		# IPv4 failed. Try the private IP to see if the service is running but not accessible (except DNS because a different service runs on the private IP).
		elif service["port"] != 53 and try_connect("127.0.0.1"):
			output.print_error("%s is running but is not publicly accessible at %s:%d." % (service['name'], env['PUBLIC_IP'], service['port']))
		else:
			output.print_error("%s is not running (port %d)." % (service['name'], service['port']))

		# Why is nginx not running?
		if not running and service["port"] in (80, 443):
			output.print_line(shell('check_output', ['nginx', '-t'], capture_stderr=True, trap=True)[1].strip())

	else:
		# Service should be running locally.
		if try_connect("127.0.0.1"):
			running = True
		else:
			output.print_error("%s is not running (port %d)." % (service['name'], service['port']))

	# Flag if local DNS is not running.
	if not running and service["port"] == 53 and service["public"] == False:
		fatal = True

	return (i, running, fatal, output)


def check_hostname_dns(env, output):
	domain = env['PRIMARY_HOSTNAME']
	ans =query_dns(domain, "A")
	if ans != env['PUBLIC_IP']:
		output.print_error("Hostname '%s' does not resolve to this machine %s" % (env["PRIMARY_HOSTNAME"], ans))
	else:
		output.print_ok("Hostname '%s' resolves to this machine (%s)" % (env["PRIMARY_HOSTNAME"], ans))

def check_certificate_status(env, output, rounded_values=False):
	domain = env['PRIMARY_HOSTNAME']
	ssl_certificates = get_ssl_certificates(env)
	tls_cert = get_domain_ssl_files(domain, ssl_certificates, env)
	if not os.path.exists(tls_cert["certificate"]):
		output.print_error("Certificate does not exist: %s" % tls_cert["certificate"])
		return
	cert_status, cert_status_details = check_certificate(domain, tls_cert["certificate"], tls_cert["private-key"], rounded_time=rounded_values)
	if cert_status == "SELF-SIGNED":
		output.print_error("SSL/TLS certificate is self-signed")
		return
	if cert_status != "OK":
		if ("%s" % cert_status_details) == "None":
			cert_status_details = ""
		output.print_error("Certificate status: %s %s" % (cert_status, cert_status_details))
		return
	output.print_ok("%s" % cert_status_details)	
        
def run_system_checks(rounded_values, env, output):
	check_ssh_password(env, output)
	check_software_updates(env, output)
	check_free_disk_space(rounded_values, env, output)
	check_free_memory(rounded_values, env, output)

def run_network_checks(env, output, rounded_values):
	# Also see setup/network-checks.sh.
	output.add_heading("Network")
	check_ufw(env, output)
	check_hostname_dns(env, output)
	check_certificate_status(env, output, rounded_values)

def run_services_checks(env, output, pool):
	# Check that system services are running.
	all_running = True
	fatal = False
	ret = pool.starmap(check_service, ((i, service, env) for i, service in enumerate(get_services())), chunksize=1)
	for i, running, fatal2, output2 in sorted(ret):
		if output2 is None: continue # skip check (e.g. no port was set, e.g. no sshd)
		all_running = all_running and running
		fatal = fatal or fatal2
		output2.playback(output)

	if all_running:
		output.print_ok("All system services are running.")

	return not fatal

        
def run_checks(rounded_values, env, output, pool):
	# run systems checks
	output.add_heading("System")

	run_services_checks(env, output, pool)
	run_system_checks(rounded_values, env, output)
	run_network_checks(env, output, rounded_values)


def run_and_output_changes(env, pool):
	import json
	from difflib import SequenceMatcher

	out = ConsoleOutput()

	# Run status checks.
	cur = BufferedOutput()
	run_checks(True, env, cur, pool)

	# Load previously saved status checks.
	cache_fn = "/var/cache/cloudinabox/status_checks.json"
	if os.path.exists(cache_fn):
		prev = json.load(open(cache_fn))

		# Group the serial output into categories by the headings.
		def group_by_heading(lines):
			from collections import OrderedDict
			ret = OrderedDict()
			k = []
			ret["No Category"] = k
			for line_type, line_args, line_kwargs in lines:
				if line_type == "add_heading":
					k = []
					ret[line_args[0]] = k
				else:
					k.append((line_type, line_args, line_kwargs))
			return ret
		prev_status = group_by_heading(prev)
		cur_status = group_by_heading(cur.buf)

		# Compare the previous to the current status checks
		# category by category.
		for category, cur_lines in cur_status.items():
			if category not in prev_status:
				out.add_heading(category + " -- Added")
				BufferedOutput(with_lines=cur_lines).playback(out)
			else:
				# Actual comparison starts here...
				prev_lines = prev_status[category]
				def stringify(lines):
					return [json.dumps(line) for line in lines]
				diff = SequenceMatcher(None, stringify(prev_lines), stringify(cur_lines)).get_opcodes()
				for op, i1, i2, j1, j2 in diff:
					if op == "replace":
						out.add_heading(category + " -- Previously:")
					elif op == "delete":
						out.add_heading(category + " -- Removed")
					if op in ("replace", "delete"):
						BufferedOutput(with_lines=prev_lines[i1:i2]).playback(out)

					if op == "replace":
						out.add_heading(category + " -- Currently:")
					elif op == "insert":
						out.add_heading(category + " -- Added")
					if op in ("replace", "insert"):
						BufferedOutput(with_lines=cur_lines[j1:j2]).playback(out)

		for category, prev_lines in prev_status.items():
			if category not in cur_status:
				out.add_heading(category)
				out.print_warning("This section was removed.")

	# Store the current status checks output for next time.
	os.makedirs(os.path.dirname(cache_fn), exist_ok=True)
	with open(cache_fn, "w") as f:
		json.dump(cur.buf, f, indent=True)



if __name__ == "__main__":
	from utils import load_environment

	env = load_environment()
	with multiprocessing.pool.Pool(processes=10) as pool:

		if len(sys.argv) == 1:
			run_checks(False, env, ConsoleOutput(), pool)

		elif sys.argv[1] == "--show-changes":
			run_and_output_changes(env, pool)

		elif sys.argv[1] == "--check-primary-hostname":
			# See if the primary hostname appears resolvable and has a signed certificate.
			domain = env['PRIMARY_HOSTNAME']
			if query_dns(domain, "A") != env['PUBLIC_IP']:
				sys.exit(1)
			ssl_certificates = get_ssl_certificates(env)
			tls_cert = get_domain_ssl_files(domain, ssl_certificates, env)
			if not os.path.exists(tls_cert["certificate"]):
				sys.exit(1)
			cert_status, cert_status_details = check_certificate(domain, tls_cert["certificate"], tls_cert["private-key"], warn_if_expiring_soon=False)
			if cert_status != "OK":
				sys.exit(1)
			sys.exit(0)

		elif sys.argv[1] == "--version":
			print(what_version_is_this(env))
