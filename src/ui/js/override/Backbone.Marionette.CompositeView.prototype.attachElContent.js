Backbone.Marionette.CompositeView.prototype.attachElContent = function (html) {

    this.$el.html(html);


    if (this.el.tagName.toLowerCase() == Backbone.Marionette.View.prototype.tagName.toLowerCase()) {
        var child = this.el.children[0];
        this.setElement(child);

        if (this.className) {
            this.el.className = this.className;
        }
        if (child.className) {
            this.el.className += " " + child.className;


        }
        /* if (child.className && !this.id) {
             this.el.id = child.id;
         }*/

    }
    return this;
}
