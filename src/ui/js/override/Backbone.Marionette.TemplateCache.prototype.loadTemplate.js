Backbone.Marionette.TemplateCache.prototype.loadTemplate = function (templateId) {
	
	var res = "<div></div>";
	Backbone.$.ajax({
		// url: "js/template/" + name + ".tpl",
		url: "Content/tpl/" + templateId + ".html",
		dateType: "html",
		async: false,
		timeout: 10000,
		success: function (data) {
		    res = data;
            
		},
		error: function () {
			
			throw new Marionette.Error({
				name: 'NoTemplateError',
				message: 'Could not load template: "' + templateId + '"'
			});
		}
	})

	return res;
}