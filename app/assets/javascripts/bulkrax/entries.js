$( document ).on('turbolinks:load ready', function() {
  $( "button" ).click(function() {
    $( "#error_trace" ).toggle();
  });
})
