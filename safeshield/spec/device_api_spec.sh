# shellcheck shell=sh

Describe 'SafeShield device API integration'
	It 'uses the generic device sync endpoint with device authentication'
		When call ss_case_device_api_contract
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'waits cleanly when the SmartSafeHub device credential is unavailable'
		When call ss_case_device_registration_pending
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
