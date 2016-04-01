Xupnpd.module("PlayList", function (PlayList, Xupnpd, Backbone, Marionette, $, _) {



    PlayList.Itemview = Backbone.Marionette.ItemView.extend({
       template: "#PlayList-item",
       events:{
         "click .remove-js":"remove"
       },
       initialize: function (paramId) {
       },
       remove:function(){
          this.model.destroy();

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
           "sync": "onSyncModel"/*,
           "change:currentQuestionId": "onChangeCurrentQuestionId"*/
       },
      initialize: function (paramId) {
           this.collection = new PlayList.collection();
           this.collection.fetch();

       },
       onSyncModel:function(){
         this.render();
       },
       onRefresh:function(event){
         debugger;
         event.preventDefault();
         this.model.fetch();
       }
  });
});
