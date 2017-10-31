Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {


    PlayList.Router = Marionette.AppRouter.extend({
        appRoutes: {
            // "info": "showInfo",
            "PlayList": "show",
            "PlayList/:id": "showListPlaylist"
        }
    });

    var API = {
        show: function () {
            var view = new PlayList.view();
            Xupnpd.mainRegion.show(view);

        },
        showListPlaylist: function (id) {
            var view = new PlayList.view(id);
            Xupnpd.mainRegion.show(view);

        }
    };

    Xupnpd.on("PlayList:show", function () {
        Xupnpd.navigate("PlayList");
        API.show();
    });

    Xupnpd.on("PlayList:showPlayList", function (id) {
        Xupnpd.navigate("PlayList/"+id);
        API.showListPlaylist(id);
    });


   Xupnpd.addInitializer(function () {
       new PlayList.Router({
           controller: API
       });
   });


});
