# SafeShield statistics: IPv4/IPv6 client identity resolution.
# Loaded together with the other statistics/*.awk modules by safeshield-statsd.

function normalize_client_id(value, mac,    normalized, flat, mac_flat) {
	normalized = tolower(value)
	if (normalized == "" || normalized == "*") {
		return ""
	}

	# A DHCP client-id of type 1 merely embeds the current Ethernet MAC and does
	# not add any stability when Android/iOS private MAC rotation is in use.
	flat = normalized
	gsub(/[:.-]/, "", flat)
	mac_flat = tolower(mac)
	gsub(/:/, "", mac_flat)
	if (mac_flat != "" && flat == ("01" mac_flat)) {
		return ""
	}

	return normalized
}

function normalize_duid(value,    normalized) {
	normalized = tolower(value)
	gsub(/[:.-]/, "", normalized)
	if (normalized == "" || normalized !~ /^[0-9a-f]+$/) {
		return ""
	}
	return normalized
}

function hostname_identity_key(value,    normalized) {
	normalized = tolower(value)
	gsub(/^[[:space:]]+|[[:space:]]+$/, "", normalized)
	return normalized
}

function hostname_is_mergeable(value,    normalized) {
	normalized = hostname_identity_key(value)
	if (normalized == "" || normalized == "*" || normalized == "unknown") {
		return 0
	}

	# Generic factory/default hostnames are hints at best and can easily belong
	# to multiple devices on the same LAN. Never use them for automatic merges.
	if (normalized == "iphone" || normalized == "ipad" || normalized == "android" || \
		normalized == "galaxy" || normalized == "phone" || normalized == "tablet" || \
		normalized == "laptop" || normalized == "desktop" || normalized == "pc" || \
		normalized == "openwrt" || normalized == "router" || normalized == "localhost") {
		return 0
	}
	return 1
}

function add_ipv6_neighbor(line,    fields, count, i, ip, mac) {
	count = split(line, fields, /[[:space:]]+/)
	if (count < 5) {
		return
	}

	ip = fields[1]
	mac = ""
	for (i = 2; i < count; i++) {
		if (fields[i] == "lladdr") {
			mac = normalize_mac(fields[i + 1])
			break
		}
	}

	if (ip == "" || mac == "") {
		return
	}

	# Keep DHCP metadata authoritative when it already knows this exact address.
	# The NDP table fills only the missing link-layer mapping.
	if (!(ip in lease_mac)) {
		lease_mac[ip] = mac
	}
	if (!(ip in lease_hostname)) {
		lease_hostname[ip] = ""
	}
}

function refresh_ipv6_neighbors(    line) {
	if (ipv6_neigh_file != "") {
		while ((getline line < ipv6_neigh_file) > 0) {
			add_ipv6_neighbor(line)
		}
		close(ipv6_neigh_file)
		return
	}

	if (ipv6_neigh_command == "") {
		return
	}

	# `ip -6 neigh show` resolves IPv6 privacy/temporary addresses back to a
	# link-layer address without storing the queried IPv6 address as identity.
	while ((ipv6_neigh_command | getline line) > 0) {
		add_ipv6_neighbor(line)
	}
	close(ipv6_neigh_command)
}

function add_ipv6_identity(line,    fields, count, ip, duid, hostname) {
	count = split(line, fields, /[\t]+/)
	if (count < 2) {
		return
	}

	ip = fields[1]
	duid = normalize_duid(fields[2])
	hostname = (count >= 3 && fields[3] != "*") ? fields[3] : ""
	if (ip == "" || duid == "") {
		return
	}

	lease_duid[ip] = duid
	if (!(ip in lease_hostname) || lease_hostname[ip] == "") {
		lease_hostname[ip] = hostname
	}
}

function refresh_ipv6_identities(    line) {
	if (ipv6_identity_file != "") {
		while ((getline line < ipv6_identity_file) > 0) {
			add_ipv6_identity(line)
		}
		close(ipv6_identity_file)
		return
	}

	if (ipv6_identity_command == "") {
		return
	}

	while ((ipv6_identity_command | getline line) > 0) {
		add_ipv6_identity(line)
	}
	close(ipv6_identity_command)
}

function clear_identity_cache(    ip) {
	for (ip in identity_key_cache) {
		delete identity_key_cache[ip]
		delete identity_cache_expires[ip]
	}
}

function cache_identity_key(ip, key, now) {
	if (ip == "" || key == "") {
		return key
	}
	identity_key_cache[ip] = key
	identity_cache_expires[ip] = now + identity_cache_ttl
	return key
}

function clear_lease_identity(    ip, key) {
	for (ip in lease_mac) {
		delete lease_mac[ip]
	}
	for (ip in lease_hostname) {
		delete lease_hostname[ip]
	}
	for (ip in lease_client_id) {
		delete lease_client_id[ip]
	}
	for (ip in lease_duid) {
		delete lease_duid[ip]
	}
	for (key in active_mac) {
		delete active_mac[key]
		delete active_mac_ip[key]
		delete active_mac_hostname[key]
		delete active_mac_client_id[key]
		delete active_mac_duid[key]
	}
	for (key in active_hostname_count) {
		delete active_hostname_count[key]
		delete active_hostname_mac[key]
	}
	for (key in active_hostname_pair) {
		delete active_hostname_pair[key]
	}
}

function rebuild_active_identity_index(    ip, mac, hostname, hostname_key, pair, client_id, duid) {
	for (ip in lease_mac) {
		mac = lease_mac[ip]
		if (mac == "") {
			continue
		}
		active_mac[mac] = 1
		if (active_mac_ip[mac] == "" || ip !~ /:/) {
			active_mac_ip[mac] = ip
		}

		hostname = lease_hostname[ip]
		if (hostname != "" && hostname != "*") {
			active_mac_hostname[mac] = hostname
			hostname_key = hostname_identity_key(hostname)
			pair = hostname_key SUBSEP mac
			if (hostname_key != "" && !(pair in active_hostname_pair)) {
				active_hostname_pair[pair] = 1
				active_hostname_count[hostname_key]++
				active_hostname_mac[hostname_key] = mac
			}
		}

		client_id = lease_client_id[ip]
		duid = lease_duid[ip]
		if (client_id != "") {
			active_mac_client_id[mac] = client_id
		}
		if (duid != "") {
			active_mac_duid[mac] = duid
		}
	}
}

function move_device_hours(from_key, to_key,    composite, parts, bucket, target, count, i, move_keys) {
	if (from_key == to_key) {
		return
	}

	# Do not mutate the associative array while iterating over it. Some awk
	# implementations may skip entries when keys are added/deleted during the
	# same for-in traversal, leaving orphan identity buckets behind.
	count = 0
	for (composite in device_hour_queries) {
		split(composite, parts, SUBSEP)
		if (parts[1] == from_key) {
			move_keys[++count] = composite
		}
	}

	for (i = 1; i <= count; i++) {
		composite = move_keys[i]
		split(composite, parts, SUBSEP)
		bucket = parts[2] + 0
		target = device_bucket_key(to_key, bucket)
		device_hour_queries[target] += device_hour_queries[composite] + 0
		device_hour_blocked[target] += device_hour_blocked[composite] + 0
		delete device_hour_queries[composite]
		delete device_hour_blocked[composite]
		delete move_keys[i]
	}

	delete device_has_hourly[from_key]
	if (count > 0) {
		device_has_hourly[to_key] = 1
	}
}

function migrate_device(from_key, to_key, mac, ip, hostname, client_id, duid,    old_client_id, old_duid, selected) {
	if (to_key == "") {
		return ""
	}
	if (from_key == "" || !(from_key in device_seen) || from_key == to_key) {
		return register_device(to_key, mac, ip, hostname, client_id, duid)
	}

	old_client_id = device_client_id[from_key]
	old_duid = device_duid[from_key]
	if (client_id == "") {
		client_id = old_client_id
	}
	if (duid == "") {
		duid = old_duid
	}
	if (hostname == "") {
		hostname = device_hostname[from_key]
	}
	if (ip == "") {
		ip = device_ip[from_key]
	}

	# A migration replaces the old logical identity atomically in the retained
	# statistics dataset. Journal the tombstone and a full replacement device so
	# a reboot cannot resurrect the old MAC/IP identity.
	if (!journal_replaying) {
		journal_deleted_device[from_key] = 1
	}
	remove_device_metadata(from_key)
	selected = register_device(to_key, mac, ip, hostname, client_id, duid)
	if (selected == "") {
		return ""
	}
	move_device_hours(from_key, selected)
	if (!journal_replaying) {
		journal_full_device[selected] = 1
	}
	return selected
}

function resolve_device_identity(ip, mac, hostname, client_id, duid,    selected, owner, ip_key) {
	if (mac == "") {
		return register_device("ip:" ip, "", ip, hostname, client_id, duid)
	}

	selected = mac
	client_id = normalize_client_id(client_id, mac)
	duid = normalize_duid(duid)

	# Strong identifiers survive private/randomized MAC changes. Move the full
	# retained history to the currently observed MAC so existing Hub schema-v3
	# consumers keep the id == mac contract while SafeShield emits one device.
	if (duid != "") {
		owner = duid_owner[duid]
		if (owner != "" && owner != selected) {
			selected = migrate_device(owner, selected, mac, ip, hostname, client_id, duid)
		}
	}
	if (client_id != "") {
		owner = client_id_owner[client_id]
		if (owner != "" && owner != selected) {
			selected = migrate_device(owner, selected, mac, ip, hostname, client_id, duid)
		}
	}

	ip_key = "ip:" ip
	if (ip_key in device_seen && ip_key != selected) {
		selected = migrate_device(ip_key, selected, mac, ip, hostname, client_id, duid)
	}
	return register_device(selected, mac, ip, hostname, client_id, duid)
}

function devices_have_conflicting_strong_identity(left, right) {
	if (device_client_id[left] != "" && device_client_id[right] != "" && \
		device_client_id[left] != device_client_id[right]) {
		return 1
	}
	if (device_duid[left] != "" && device_duid[right] != "" && device_duid[left] != device_duid[right]) {
		return 1
	}
	return 0
}

function reconcile_hostname_devices(    hostname_key, target_mac, target_key, target_ip, target_hostname, target_client_id, target_duid, key, count, i, candidates) {
	for (hostname_key in active_hostname_count) {
		if ((active_hostname_count[hostname_key] + 0) != 1 || !hostname_is_mergeable(hostname_key)) {
			continue
		}

		target_mac = active_hostname_mac[hostname_key]
		if (target_mac == "") {
			continue
		}
		target_key = target_mac
		target_ip = active_mac_ip[target_mac]
		target_hostname = active_mac_hostname[target_mac]
		target_client_id = active_mac_client_id[target_mac]
		target_duid = active_mac_duid[target_mac]
		target_key = register_device(target_key, target_mac, target_ip, target_hostname, target_client_id, target_duid)
		if (target_key == "") {
			continue
		}

		count = 0
		for (key in device_seen) {
			if (key == target_key || device_mac[key] == "" || device_mac[key] in active_mac) {
				continue
			}
			if (hostname_identity_key(device_hostname[key]) != hostname_key) {
				continue
			}
			if (devices_have_conflicting_strong_identity(key, target_key)) {
				continue
			}
			candidates[++count] = key
		}

		for (i = 1; i <= count; i++) {
			key = candidates[i]
			target_key = migrate_device(key, target_key, target_mac, target_ip, target_hostname, target_client_id, target_duid)
			delete candidates[i]
		}
	}
}

function reconcile_ip_devices(    ip, ip_key, mac, hostname, client_id, duid, owner) {
	for (ip in lease_mac) {
		mac = lease_mac[ip]
		if (mac == "") {
			continue
		}
		hostname = lease_hostname[ip]
		client_id = lease_client_id[ip]
		duid = lease_duid[ip]
		ip_key = "ip:" ip

		# Avoid materializing every DHCP/NDP lease as a zero-counter device.
		# Reconcile eagerly only when retained history or a strong identity owner
		# already exists; normal traffic registers a new active device on demand.
		owner = ""
		if (duid != "") {
			owner = duid_owner[duid]
		}
		if (owner == "" && client_id != "") {
			owner = client_id_owner[client_id]
		}
		if (!(ip_key in device_seen) && !(mac in device_seen) && owner == "") {
			continue
		}
		resolve_device_identity(ip, mac, hostname, client_id, duid)
	}
}

function refresh_leases(now, force,    line, fields, count, mac, ip, hostname, client_id) {
	if (!force && last_lease_refresh > 0 && (now - last_lease_refresh) < lease_refresh_interval) {
		return
	}

	clear_identity_cache()
	clear_lease_identity()

	while ((getline line < lease_file) > 0) {
		count = split(line, fields, /[[:space:]]+/)
		if (count < 4) {
			continue
		}

		mac = normalize_mac(fields[2])
		ip = fields[3]
		hostname = fields[4]
		client_id = (count >= 5) ? normalize_client_id(fields[5], mac) : ""
		if (mac == "" || ip == "") {
			continue
		}

		lease_mac[ip] = mac
		lease_hostname[ip] = (hostname == "*") ? "" : hostname
		lease_client_id[ip] = client_id
	}
	close(lease_file)

	# DHCP leases are not guaranteed to contain every active client. Static-IP
	# clients and lease-file update windows can otherwise recreate an ip:*
	# identity after the device has already been identified by MAC. Use the
	# kernel ARP table as the current IPv4 identity fallback.
	while ((getline line < arp_file) > 0) {
		count = split(line, fields, /[[:space:]]+/)
		if (count < 4) {
			continue
		}

		ip = fields[1]
		mac = normalize_mac(fields[4])
		if (ip == "" || mac == "") {
			continue
		}

		if (!(ip in lease_mac)) {
			lease_mac[ip] = mac
			lease_hostname[ip] = ""
			lease_client_id[ip] = ""
		}
	}
	close(arp_file)

	# odhcpd exposes the DHCPv6 DUID while the kernel NDP cache exposes the MAC.
	# Combining the two lets privacy IPv6 addresses and private MAC rotations
	# converge without treating each temporary IPv6 address as a new device.
	refresh_ipv6_identities()
	refresh_ipv6_neighbors()
	rebuild_active_identity_index()
	reconcile_ip_devices()
	reconcile_hostname_devices()

	last_lease_refresh = now
}

function compact_stale_provisional_devices(now,    cutoff, key, last_bucket, count, i, stale) {
	cutoff = hour_start(now) - (provisional_retention_hours * 3600)
	count = 0
	for (key in device_seen) {
		if (key !~ /^ip:/ || device_client_id[key] != "" || device_duid[key] != "") {
			continue
		}
		last_bucket = device_last_bucket[key] + 0
		if (last_bucket > 0 && last_bucket <= cutoff) {
			stale[++count] = key
		}
	}

	for (i = 1; i <= count; i++) {
		key = stale[i]
		migrate_device(key, "unknown", "", "", "Unknown devices", "", "")
		delete stale[i]
	}
	return count
}

function is_internal_statistics_client(ip) {
	return (ip == "::1" || ip ~ /^127\./)
}

function device_key_for_ip(ip, now,    cached_key, mac, hostname, client_id, duid, selected) {
	if (ip == "" || is_internal_statistics_client(ip)) {
		return ""
	}

	if ((ip in identity_key_cache) && (identity_cache_expires[ip] + 0) > now) {
		cached_key = identity_key_cache[ip]
		if (cached_key != "") {
			return cached_key
		}
	}
	delete identity_key_cache[ip]
	delete identity_cache_expires[ip]

	refresh_leases(now, 0)
	mac = lease_mac[ip]
	hostname = lease_hostname[ip]
	client_id = lease_client_id[ip]
	duid = lease_duid[ip]
	if (mac != "") {
		selected = resolve_device_identity(ip, mac, hostname, client_id, duid)
	}
	else {
		selected = register_device("ip:" ip, "", ip, hostname, client_id, duid)
	}

	return cache_identity_key(ip, selected, now)
}

function record_device(ip, query_delta, blocked_delta, now,    key, bucket, composite) {
	key = device_key_for_ip(ip, now)
	if (key == "") {
		return
	}

	bucket = hour_start(now)
	composite = device_bucket_key(key, bucket)
	device_hour_queries[composite] += 0
	device_hour_blocked[composite] += 0
	if (query_delta > 0) {
		device_hour_queries[composite] += query_delta
	}
	if (blocked_delta > 0) {
		device_hour_blocked[composite] += blocked_delta
	}
	device_has_hourly[key] = 1
}
