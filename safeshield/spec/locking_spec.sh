#!/bin/sh
# shellcheck shell=sh

Describe 'SafeShield directory locking and state consistency'
	It 'prevents lock theft, reclaims stale owners and respects ownership'
		When call ss_case_lock_owner_and_contention
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'serializes concurrent operations using BusyBox-compatible locks'
		When call ss_case_lock_parallel
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'serializes status read-modify-write operations under the same lock'
		When call ss_case_status_write_serialization
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'does not corrupt the previous status when serialization fails'
		When call ss_case_status_write_failure
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
