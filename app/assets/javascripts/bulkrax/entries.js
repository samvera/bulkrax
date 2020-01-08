$( document ).on('turbolinks:load ready', function() {
  console.log("Entries Loaded");
  $( "button" ).click(function() {
    $( "#error_trace" ).toggle();
  });
})
