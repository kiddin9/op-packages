# shellcheck shell=sh

Describe 'SafeShield ucode modules'
	It 'compiles modules and runs the ucode regression suite when available'
		When call ss_case_ucode
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
