'use strict';
'require baseclass';

return baseclass.extend({
	parseDocument: function() {
		throw new Error(_('YAML AST editing is not available in the compact package helper.'));
	},
	isMap: function() { return false; },
	isSeq: function() { return false; }
});
