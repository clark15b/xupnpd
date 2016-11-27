Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {
    PlayList.model = Backbone.Model.extend({
       urlRoot: function(){
         return "api_v2/playlist";
       },
        defaults: {
            name: "-",
            id: ""

        }
    });

    PlayList.modelDetail = Backbone.Model.extend({
        defaults: {
            name: "-",
            id: "",
            url: ""

        }
    });
});
