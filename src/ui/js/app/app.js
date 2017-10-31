var Xupnpd = new Marionette.Application();

Xupnpd.addRegions({
    mainRegion: "#main-region",
    modal: "#modal-window-region"

});


Xupnpd.navigate = function (route, options) {
    options || (options = {});
    Backbone.history.navigate(route, options);
};


Xupnpd.getCurrentRoute = function () {
    return Backbone.history.fragment
};

Xupnpd.closeModal = function () {
    Xupnpd.modal.reset()
};

Xupnpd.loadMask = {


    _selector: "#loading",
    show: function () {
        $(this._selector).show();

    },
    hide: function () {
        $(this._selector).hide();
    }

}
Xupnpd.on("modalWindow:close", function (param) {
    Xupnpd.closeModal();
});
/*
 Xupnpd.addInitializer(function () {
 // console.log("Запуск инициализации");

 if (this.getCurrentRoute() === "") {
 Xupnpd.trigger("about:show");
 }

 });
 */
Xupnpd.token = "azaza";
Xupnpd.message = function (msg, type) {
    alert(msg);
};

Xupnpd.cache = {};

Xupnpd.on("start", function (options) {
    /*
     if (!sessionStorage.getItem("token")) {
     document.location = "/Home/Login";
     } else {
     Xupnpd.token = sessionStorage.getItem("token");
     }
     */


    if (Backbone.history) {
        Backbone.history.start();
    }
    var urlPath =  document.location.pathname.match("/ui/(.+)");
    if( !urlPath || urlPath.length > 1 && urlPath[1] == "ui_template.html"){
        if (this.getCurrentRoute() === "" ) {
            Xupnpd.trigger("Status:show");
        }
    }


});

Xupnpd.addInitializer(function (options) {

    console.log("Запуск инициализации");

    //Xupnpd.cache.personel = new Xupnpd.Common.CachePersonel();
    //Xupnpd.cache.personel.fetch();

});


$(function () {
    Xupnpd.start();
})
