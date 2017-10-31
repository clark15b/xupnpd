Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {

  PlayList.collection = Backbone.Collection.extend({
    model: PlayList.model,
    url: "api_v2/playlist"
  });
  PlayList.collectionDetail = Backbone.Collection.extend({
    model: PlayList.modelDetail,
    url: "api_v2/playlist"
  });





});
