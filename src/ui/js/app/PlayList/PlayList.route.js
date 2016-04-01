Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {


    PlayList.Router = Marionette.AppRouter.extend({
        appRoutes: {
            // "info": "showInfo",
            "PlayList": "show"
        }
    });

    var API = {
        show: function () {
            var view = new PlayList.view();
            Xupnpd.mainRegion.show(view);

        }
    };

    Xupnpd.on("PlayList:show", function () {
        Xupnpd.navigate("PlayList");
        API.show();
    });

  

   Xupnpd.addInitializer(function () {
       new PlayList.Router({
           controller: API
       });
   });


});
