Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {



    PlayList.Itemview = Backbone.Marionette.ItemView.extend({
       template: "#PlayList-item",
       events:{
         "click .remove-js": "removePlaylist",
         "click .detail-js": "showSubVideo"
       },
       initialize: function (paramId) {
       },
       removePlaylist:function(){
         if(confirm("Delete?")){
          this.model.destroy({});
        }
       },
       showSubVideo:function(){
         document.location = "/ui/show?fname=" + this.model.id + ".m3u";
       }

    });

   PlayList.view = Backbone.Marionette.CompositeView.extend({
      template: "#PlayList-main",
      childView:PlayList.Itemview,
      childViewContainer:"tbody",
      events:{
        "click .refresh-js":"onRefresh"
      },
       modelEvents: {
           "sync": "onSyncModel"
       },
       modelEvents: {
           "sync": "onSyncModel"
       },
       collectionEvents: {
            "sync": "onSyncCollection"
        },
      initialize: function (paramId) {
           this.collection = new PlayList.collection();
           this.collection.fetch();

       },
       onSyncModel:function(){
         this.render();
       },
       onSyncCollection:function(){
         this.render();
       },
       onRefresh:function(event){
         debugger;
         event.preventDefault();
         this.model.fetch();
       }
  });
});
