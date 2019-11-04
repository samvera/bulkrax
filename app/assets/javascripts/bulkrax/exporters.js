jQuery(function() {
	$( '.exporter_export_from' ).change(function() {
		// get the selected export_from option
		var opt = $( '.exporter_export_from option:selected' ).val();
		unhideSelected(opt);
	});
});

function unhideSelected(field) {
	// hide all export_source
	var source_div = $( 'body' ).find( '.exporter_export_source')
	source_div.addClass('hidden');
	source_div.find( '#exporter_export_source').addClass('hidden').attr('type', 'hidden');
	// unhide selected export_source
	var selected_source = source_div.find('.' + field)
	selected_source.removeClass('hidden').removeAttr('type');
	selected_source.parent().removeClass('hidden').removeAttr('type');
};

