// SPDX-License-Identifier: Apache-2.0

'use strict';
'require form';
'require fs';
'require ui';
'require view';
'require rpc';
'require uci';

var callFileWrite = rpc.declare({
	object: 'file',
	method: 'write',
	params: [ 'path', 'data' ]
});

var configFile = '/etc/meow/config.yaml';

return view.extend({
	editorInstance: null,

	handleSaveApply: function (ev, mode) {
		var value = document.getElementById('cbid_meow_config__configuration').value;

		if (!value) {
			ui.addNotification(null, E('p', _('Configuration cannot be empty!')), 'error');
			return Promise.reject(new Error('Empty configuration'));
		}

		if (this.editorInstance) {
			var model = this.editorInstance.getModel();
			var markers = monaco.editor.getModelMarkers({
				owner: 'meow-validator',
				resource: model.uri
			});

			if (markers && markers.length > 0) {
				var errorMessages = markers.map(function (marker) {
					return marker.message + ' ' + _('(Line: %d)').format(marker.startLineNumber);
				}).join('<br>');

				ui.addNotification(null, E('p', [
					_('Configuration validation failed!'),
					E('br'),
					E('small', errorMessages)
				]), 'error');

				return Promise.reject(new Error('Invalid configuration'));
			}
		}

		return callFileWrite(configFile, value)
			.then(function () {
				return L.resolveDefault(
					fs.exec_direct('/bin/chmod', [ '0600', configFile ]),
					null
				);
			})
			.then(function () {
				/*
				 * fs.exec_direct resolves with stdout and rejects
				 * on non-zero exit code.
				 *
				 * It does not return an object containing `code`.
				 * Reload first, restart only when reload fails.
				 */
				return fs.exec_direct('/etc/init.d/meow', [ 'reload' ])
					.catch(function () {
						return fs.exec_direct('/etc/init.d/meow', [ 'restart' ]);
					});
			})
			.catch(function (e) {
				ui.addNotification(
					null,
					E('p', _('Failed to save configuration: %s').format(e.message))
				);

				return Promise.reject(e);
			});
	},

	load: function () {
		return fs.read_direct(configFile, 'text')
			.then(function (content) {
				return content ?? '';
			})
			.catch(function (e) {
				ui.addNotification(null, E('p', e.message));
				return '';
			});
	},

	render: function (content) {
		var m, s;
		var self = this;

		self.formvalue = {};

		var css = E('style', {}, `
			#code_editor {
				height: 500px;
				width: 100%;
				border: 1px solid #ccc;
			}
			#fallback_editor {
				height: 500px;
				width: 100%;
				font-family: monospace;
				white-space: pre;
			}
			@media (prefers-color-scheme: dark) {
				#code_editor {
					border-color: #555;
				}
				#fallback_editor {
					background: #1e1e1e;
					color: #d4d4d4;
				}
			}
		`);

		var editorDiv = E('div', { id: 'code_editor' });

		var hiddenInput = E('input', {
			type: 'hidden',
			id: 'cbid_meow_config__configuration',
			name: 'cbid.meow.config._configuration',
			value: content
		});

		m = new form.Map(
			'meow',
			_('Configuration'),
			_('Here you can edit the meow YAML configuration. It will be automatically validated and the service reloaded after apply.')
		);

		m.onValidate = function (map, data) {
			self.formvalue = data;
		};

		m.submitSave = function () {
			return false;
		};

		s = m.section(form.TypedSection);
		s.anonymous = true;

		s.render = function () {
			return E('div', { 'class': 'cbi-section' }, [
				css,
				editorDiv,
				hiddenInput
			]);
		};

		var formEl = m.render();

		window.setTimeout(function () {

			function buildFallbackTextarea(initialValue) {
				var ta = E('textarea', {
					id: 'fallback_editor',
					'style': 'height:500px;width:100%'
				});

				ta.value = initialValue;

				ta.addEventListener('input', function () {
					hiddenInput.value = ta.value;
					self.formvalue.cbid_meow_config__configuration = ta.value;
				});

				editorDiv.parentNode.replaceChild(ta, editorDiv);
			}

			var loaderScript = document.createElement('script');
			loaderScript.src = '/luci-static/resources/monaco-editor/min/vs/loader.js';
			document.head.appendChild(loaderScript);

			loaderScript.onerror = function () {
				buildFallbackTextarea(content);
			};

			loaderScript.onload = function () {
				require.config({
					paths: {
						'vs': '/luci-static/resources/monaco-editor/min/vs'
					},
					'vs/nls': {
						availableLanguages: {
							'*': 'zh-cn'
						}
					}
				});

				require([ 'vs/editor/editor.main' ], function () {
					var prefersDarkMode =
						window.matchMedia('(prefers-color-scheme: dark)').matches;

					self.editorInstance = monaco.editor.create(
						document.getElementById('code_editor'),
						{
							value: content,
							language: 'yaml',
							theme: prefersDarkMode ? 'vs-dark' : 'vs',
							automaticLayout: true,
							minimap: { enabled: false },
							scrollBeyondLastLine: false,
							lineNumbers: 'on',
							tabSize: 2,
							wordWrap: 'on'
						}
					);

					var validateTimer = null;

					function validateYamlConfig() {
						var model = self.editorInstance.getModel();
						var value = model.getValue();
						var lines = value.split('\n');
						var markers = [];

						monaco.editor.setModelMarkers(
							model,
							'meow-validator',
							[]
						);

						var bracketStack = [];
						var unmatchedBrackets = [];

						for (var i = 0; i < lines.length; i++) {
							var line = lines[i];
							var trimmed = line.trim();

							if (/^\t/.test(line)) {
								markers.push({
									severity: monaco.MarkerSeverity.Error,
									message: _('YAML does not allow tab characters for indentation'),
									startLineNumber: i + 1,
									startColumn: 1,
									endLineNumber: i + 1,
									endColumn: 2
								});
							}

							if (
								trimmed.startsWith('#') ||
								trimmed.startsWith('//') ||
								trimmed === ''
							) {
								continue;
							}

							for (var j = 0; j < line.length; j++) {
								var ch = line[j];

								if (ch === '{' || ch === '[' || ch === '(') {
									bracketStack.push({
										line: i + 1,
										char: ch,
										pos: j
									});
								} else if (ch === '}' || ch === ']' || ch === ')') {
									var openChar = {
										'}': '{',
										']': '[',
										')': '('
									}[ch];

									if (
										bracketStack.length > 0 &&
										bracketStack[bracketStack.length - 1].char === openChar
									) {
										bracketStack.pop();
									} else {
										unmatchedBrackets.push({
											line: i + 1,
											pos: j,
											type: 'closing'
										});
									}
								}
							}
						}

						unmatchedBrackets.forEach(function (bracket) {
							markers.push({
								severity: monaco.MarkerSeverity.Error,
								message: _('Found unmatched closing bracket'),
								startLineNumber: bracket.line,
								startColumn: bracket.pos + 1,
								endLineNumber: bracket.line,
								endColumn: bracket.pos + 2
							});
						});

						bracketStack.forEach(function (bracket) {
							markers.push({
								severity: monaco.MarkerSeverity.Error,
								message: _('Unclosed bracket'),
								startLineNumber: bracket.line,
								startColumn: bracket.pos + 1,
								endLineNumber: bracket.line,
								endColumn: bracket.pos + 2
							});
						});

						monaco.editor.setModelMarkers(
							model,
							'meow-validator',
							markers
						);
					}

					self.editorInstance.onDidChangeModelContent(function () {
						var value = self.editorInstance.getValue();

						hiddenInput.value = value;

						document.getElementById(
							'cbid_meow_config__configuration'
						).value = value;

						self.formvalue.cbid_meow_config__configuration = value;

						if (validateTimer) {
							clearTimeout(validateTimer);
						}

						validateTimer = setTimeout(
							validateYamlConfig,
							500
						);
					});

					setTimeout(validateYamlConfig, 1000);

					window.matchMedia(
						'(prefers-color-scheme: dark)'
					).addEventListener('change', function (e) {
						monaco.editor.setTheme(
							e.matches ? 'vs-dark' : 'vs'
						);
					});

					window.addEventListener('resize', function () {
						self.editorInstance.layout();
					});
				});
			};
		}, 100);

		return formEl;
	}
});
