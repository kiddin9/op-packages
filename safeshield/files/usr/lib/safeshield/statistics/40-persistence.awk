# SafeShield statistics: tmpfs state and persistent journal writes.
# Loaded together with the other statistics/*.awk modules by safeshield-statsd.

function save_state_file(path, now,    tmp, bucket, cutoff, key, composite, parts) {
	if (path == "") {
		return 0
	}

	tmp = path ".tmp"
	printf "meta\t%d\t%d\t%d\t%d\t%d\t%d\t6\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\n", \
		started_at, updated_at, total_queries, total_blocked, devices_truncated, \
		persistent_updated_at, session_started_at, persistence_healthy, \
		persistent_error_count, persistent_last_error_at, persistent_compacted_at, \
		last_journal_completed_bucket, normalize_state_field(generation_id), \
		snapshot_seq, snapshot_seq_reserved_through > tmp
	if (source_initialized || source_error_count > 0) {
		printf "source\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", \
			normalize_state_field(source_instance_id), \
			normalize_state_field(source_transport_scope), \
			source_client_capacity, source_tracked_clients, source_untracked_queries, \
			source_total_queries, source_total_blocked, source_available, \
			source_error_count, source_last_error_at, source_untracked_blocked >> tmp
	}
	if (source_initialized) {
		for (key in source_client_queries) {
			printf "source_client\t%s\t%d\t%d\n", \
				normalize_state_field(key), \
				source_client_queries[key] + 0, \
				source_client_blocked[key] + 0 >> tmp
		}
	}
	cutoff = hour_start(now) - ((retention_hours - 1) * 3600)
	for (bucket = cutoff; bucket <= hour_start(now); bucket += 3600) {
		if ((bucket in queries) || (bucket in blocked)) {
			printf "bucket\t%d\t%d\t%d\n", bucket, queries[bucket] + 0, blocked[bucket] + 0 >> tmp
		}
	}
	for (key in device_seen) {
		printf "device\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\n", \
			normalize_state_field(key), \
			normalize_state_field(device_mac[key]), \
			normalize_state_field(device_ip[key]), \
			normalize_state_field(device_hostname[key]), \
			device_queries[key] + 0, \
			device_blocked[key] + 0, \
			normalize_state_field(device_client_id[key]), \
			normalize_state_field(device_duid[key]) >> tmp
	}
	for (composite in device_hour_queries) {
		split(composite, parts, SUBSEP)
		if ((parts[2] + 0) < cutoff) {
			continue
		}
		printf "device_bucket\t%s\t%d\t%d\t%d\n", \
			normalize_state_field(parts[1]), \
			parts[2] + 0, \
			device_hour_queries[composite] + 0, \
			device_hour_blocked[composite] + 0 >> tmp
	}
	close(tmp)

	if (!replace_file(tmp, path)) {
		system("rm -f " shell_quote(tmp))
		return 0
	}
	return 1
}

function save_sequence_reservation(path, generation, reserved_through,    tmp) {
	if (path == "" || generation == "" || reserved_through <= 0) {
		return 0
	}

	tmp = path ".tmp"
	printf "reserve\t%s\t%d\n", normalize_state_field(generation), reserved_through > tmp
	close(tmp)
	if (!replace_file(tmp, path)) {
		system("rm -f " shell_quote(tmp))
		return 0
	}
	return 1
}

function ensure_snapshot_sequence_reservation(now,    next_seq, reserved_through) {
	next_seq = snapshot_seq + 1
	if (sequence_file == "") {
		snapshot_seq = next_seq
		if (snapshot_seq > snapshot_seq_reserved_through) {
			snapshot_seq_reserved_through = snapshot_seq
		}
		return 1
	}

	if (next_seq > snapshot_seq_reserved_through) {
		reserved_through = next_seq + snapshot_seq_reservation_size - 1
		if (!save_sequence_reservation(sequence_file, generation_id, reserved_through)) {
			persistence_healthy = 0
			persistent_error_count++
			persistent_last_error_at = now
			return 0
		}
		snapshot_seq_reserved_through = reserved_through
	}

	snapshot_seq = next_seq
	return 1
}

function append_file(source, target,    rc) {
	rc = system("cat " shell_quote(source) " >> " shell_quote(target))
	return rc == 0
}

function clear_journal_file(path,    rc) {
	if (path == "") {
		return 1
	}
	rc = system(": > " shell_quote(path))
	return rc == 0
}

function schedule_next_persistent(now) {
	next_persistent_at = hour_start(now) + persistent_interval
	while (next_persistent_at <= now) {
		next_persistent_at += persistent_interval
	}
}

function schedule_next_compaction(now) {
	if (persistent_compact_interval <= 0) {
		next_compact_at = 0
		return
	}
	if (persistent_compacted_at <= 0) {
		persistent_compacted_at = now
	}
	next_compact_at = persistent_compacted_at + persistent_compact_interval
	while (next_compact_at <= now) {
		next_compact_at += persistent_compact_interval
	}
}

function journal_has_pending_deletes(    key) {
	for (key in journal_deleted_device) {
		return 1
	}
	return 0
}

function journal_has_pending_full_devices(    key) {
	for (key in journal_full_device) {
		return 1
	}
	return 0
}

function clear_journal_pending(    key) {
	for (key in journal_deleted_device) {
		delete journal_deleted_device[key]
	}
	for (key in journal_full_device) {
		delete journal_full_device[key]
	}
}

function write_journal_transaction(now, first_bucket, last_bucket, completed_through,    tmp, txn_id, bucket, key, composite, wrote_device, device_first, device_last, cutoff) {
	if (persistent_journal_file == "") {
		return 0
	}
	if (first_bucket > last_bucket && !journal_has_pending_deletes() && !journal_has_pending_full_devices()) {
		return 1
	}

	tmp = state_file ".journal.tmp"
	txn_id = sprintf("%d-%d-%d", now, event_index, ++journal_txn_seq)
	printf "begin\t%s\t4\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\n", \
		txn_id, now, started_at, devices_truncated, session_started_at, \
		completed_through, persistence_healthy, persistent_error_count, \
		persistent_last_error_at, normalize_state_field(generation_id), \
		snapshot_seq, snapshot_seq_reserved_through > tmp

	for (key in journal_deleted_device) {
		printf "delete_device\t%s\n", normalize_state_field(key) >> tmp
	}

	for (bucket = first_bucket; bucket <= last_bucket; bucket += 3600) {
		if ((bucket in queries) || (bucket in blocked)) {
			printf "bucket\t%d\t%d\t%d\n", bucket, queries[bucket] + 0, blocked[bucket] + 0 >> tmp
		}
	}

	# Journal writes normally cover one completed hour. Iterate at most
	# max_devices for that hour instead of scanning every retained device-hour
	# entry (up to max_devices * retention_hours) on low-end routers. Identity
	# migration is the exception: its target MAC receives the full retained
	# history in the same transaction as the old ip:* tombstone.
	cutoff = hour_start(now) - ((retention_hours - 1) * 3600)
	for (key in device_seen) {
		wrote_device = 0
		device_first = first_bucket
		device_last = last_bucket
		if (key in journal_full_device) {
			device_first = cutoff
			device_last = hour_start(now)
		}
		for (bucket = device_first; bucket <= device_last; bucket += 3600) {
			composite = device_bucket_key(key, bucket)
			if (!((composite in device_hour_queries) || (composite in device_hour_blocked))) {
				continue
			}
			if (!wrote_device) {
				printf "device\t%s\t%s\t%s\t%s\t%s\t%s\n", \
					normalize_state_field(key), \
					normalize_state_field(device_mac[key]), \
					normalize_state_field(device_ip[key]), \
					normalize_state_field(device_hostname[key]), \
					normalize_state_field(device_client_id[key]), \
					normalize_state_field(device_duid[key]) >> tmp
				wrote_device = 1
			}
			printf "device_bucket\t%s\t%d\t%d\t%d\n", \
				normalize_state_field(key), bucket, \
				device_hour_queries[composite] + 0, \
				device_hour_blocked[composite] + 0 >> tmp
		}
	}
	printf "commit\t%s\n", txn_id >> tmp
	close(tmp)

	if (!append_file(tmp, persistent_journal_file)) {
		system("rm -f " shell_quote(tmp))
		return 0
	}
	system("rm -f " shell_quote(tmp))
	clear_journal_pending()
	return 1
}

function flush_completed_journal(now,    current_bucket, target_bucket, cutoff, first_bucket) {
	current_bucket = hour_start(now)
	target_bucket = current_bucket - 3600
	cutoff = current_bucket - ((retention_hours - 1) * 3600)
	first_bucket = last_journal_completed_bucket + 3600
	if (last_journal_completed_bucket <= 0 || first_bucket < cutoff) {
		first_bucket = cutoff
	}

	if (target_bucket < first_bucket && !journal_has_pending_deletes() && !journal_has_pending_full_devices()) {
		return 1
	}
	if (!write_journal_transaction(now, first_bucket, target_bucket, target_bucket)) {
		return 0
	}
	if (target_bucket >= first_bucket) {
		last_journal_completed_bucket = target_bucket
	}
	return 1
}

function flush_current_journal(now,    current_bucket) {
	current_bucket = hour_start(now)
	return write_journal_transaction(now, current_bucket, current_bucket, last_journal_completed_bucket)
}

function maybe_compact_persistent(now,    previous_compacted) {
	if (persistent_state_file == "" || persistent_journal_file == "" || persistent_compact_interval <= 0) {
		return 1
	}
	if (next_compact_at <= 0 || now < next_compact_at) {
		return 1
	}

	previous_compacted = persistent_compacted_at
	persistent_compacted_at = now
	if (!save_state_file(persistent_state_file, now)) {
		persistent_compacted_at = previous_compacted
		persistent_error_count++
		persistent_last_error_at = now
		next_compact_at = now + ((persistent_retry_interval > 3600) ? persistent_retry_interval : 3600)
		return 0
	}

	# The base snapshot is already complete. If journal truncation is interrupted,
	# startup ignores committed transactions whose updated_at is not newer than
	# the base snapshot, preventing retained absolute upserts from rolling it back.
	if (!clear_journal_file(persistent_journal_file)) {
		persistent_error_count++
		persistent_last_error_at = now
	}
	schedule_next_compaction(now)
	return 1
}

function save_persistent_snapshot(now,    previous_updated) {
	previous_updated = persistent_updated_at
	persistent_updated_at = now
	persistence_healthy = 1
	if (!save_state_file(persistent_state_file, now)) {
		persistent_updated_at = previous_updated
		persistence_healthy = 0
		persistent_error_count++
		persistent_last_error_at = now
		next_persistent_at = now + persistent_retry_interval
		return 0
	}
	persistence_healthy = 1
	return 1
}

function maybe_save_persistent(now, force,    previous_updated, ok) {
	if (persistent_state_file == "" && persistent_journal_file == "") {
		return 1
	}
	if (!force && now < next_persistent_at) {
		return 1
	}

	# Compatibility fallback for callers that do not configure a journal.
	if (persistent_journal_file == "") {
		if (!save_persistent_snapshot(now)) {
			return 0
		}
		schedule_next_persistent(now)
		return 1
	}

	previous_updated = persistent_updated_at
	persistence_healthy = 1
	ok = flush_completed_journal(now)
	if (ok && force) {
		ok = flush_current_journal(now)
	}
	if (!ok) {
		persistent_updated_at = previous_updated
		persistence_healthy = 0
		persistent_error_count++
		persistent_last_error_at = now
		next_persistent_at = now + persistent_retry_interval
		return 0
	}

	persistent_updated_at = now
	persistence_healthy = 1
	if (!force) {
		maybe_compact_persistent(now)
	}
	schedule_next_persistent(now)
	return 1
}
