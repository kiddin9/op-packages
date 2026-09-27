# shellcheck shell=sh

Describe 'SafeShield lifecycle and refresh state machines'
	It 'rolls back full refresh failures while preserving the active blocklist for upgrade-required responses'
		When call ss_case_refresh_state_machine
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'applies cached local rules idempotently and rolls back failed fast applies'
		When call ss_case_local_apply_state_machine
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'serializes full refresh and local apply workers with a termination-aware lock'
		When call ss_case_refresh_locking
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'starts and stops SafeShield safely across disabled, statistics, and migration paths'
		When call ss_case_service_lifecycle
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
