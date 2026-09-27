# shellcheck shell=sh

Describe 'SafeShield runtime process behavior'
	It 'interrupts refreshd long sleeps without one-second polling'
		When call ss_case_refreshd_wait
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'schedules refreshes without retry storms and handles boot, WAN, and disabled states'
		When call ss_case_refreshd_scheduler
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'starts and stops the statistics collector cleanly'
		When call ss_case_statistics_collector
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'uploads statistics idempotently and reconciles after failures'
		When call ss_case_statistics_uploader
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'stores Hub statistics upload credentials only in the runtime cache'
		When call ss_case_statistics_upload_credentials
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'sends the Hub statistics bearer credential as an HTTP authorization header'
		When call ss_case_statistics_http_auth
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'uses authenticated uclient-fetch safely on OpenWrt'
		When call ss_case_http_uclient_transport
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'reconciles statistics runtime without disturbing refreshd'
		When call ss_case_statistics_reconcile
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
