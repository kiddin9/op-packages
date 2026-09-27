# shellcheck shell=sh

Describe 'SafeShield test and lint integration'
	It 'uses native ShellSpec discovery and the shared lint entrypoint'
		When call ss_case_tooling
		The status should be success
		The output should equal ''
		The error should equal ''
	End

	It 'keeps retired shell helpers and unused runtime sources removed'
		When call ss_case_dead_code_contract
		The status should be success
		The output should equal ''
		The error should equal ''
	End
End
