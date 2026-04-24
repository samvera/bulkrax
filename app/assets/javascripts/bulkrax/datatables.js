function bulkraxDatatableLanguage() {
  var i18n = (window.BulkraxI18n && window.BulkraxI18n.datatable && window.BulkraxI18n.datatable.language) || {}
  return {
    emptyTable: i18n.empty_table,
    info: i18n.info,
    infoEmpty: i18n.info_empty,
    infoFiltered: i18n.info_filtered,
    lengthMenu: i18n.length_menu,
    loadingRecords: i18n.loading_records,
    processing: i18n.processing,
    search: i18n.search,
    zeroRecords: i18n.zero_records,
    paginate: {
      next: i18n.next,
      previous: i18n.previous
    }
  }
}

Blacklight.onLoad(function() {
  if($('#importer-show-table').length) {
    $('#importer-show-table').DataTable( {
      'processing': true,
      'serverSide': true,
      'width': '100%',
      'autoWidth': false,
      'scrollX': true,
      'scrollCollapse': true,
      "ajax": window.location.href.replace(/(\/(importers|exporters)\/\d+)/, "$1/entry_table.json"),
      "pageLength": 30,
      "lengthMenu": [[30, 100, 200], [30, 100, 200]],
      "language": bulkraxDatatableLanguage(),
      "columns": [
        { "data": "identifier" },
        { "data": "id" },
        { "data": "status_message" },
        { "data": "type" },
        { "data": "updated_at" },
        { "data": "errors", "orderable": false },
        { "data": "actions", "orderable": false }
      ],
      drawCallback: function() {
        // Remove the inline styles that DataTables adds to the scrollHeadInner and table elements
        // it's not perfect but better than the style being applied
        setTimeout(function() {
          $('.dataTables_scrollHeadInner').removeAttr('style');
          $('.table.table-striped.dataTable.no-footer').removeAttr('style');
        }, 100);
      },
      initComplete: function () {
        // Add entry class filter
        entrySelect.bind(this)()
        // Add status filter
        statusSelect.bind(this)()
        // Add refresh link
        refreshLink.bind(this)()
      }
    } );
  }

    if($('#importers-table').length) {
    $('#importers-table').DataTable( {
      'processing': true,
      'serverSide': true,
      "ajax": window.location.href.replace(/(\/importers)/, "$1/importer_table.json"),
      "pageLength": 30,
      "lengthMenu": [[30, 100, 200], [30, 100, 200]],
      "language": bulkraxDatatableLanguage(),
      "order": [[2, 'desc']],
      "columns": [
        { "data": "name" },
        { "data": "status_message" },
        { "data": "last_imported_at" },
        { "data": "next_import_at" },
        { "data": "enqueued_records", "orderable": false },
        { "data": "processed_records", "orderable": false },
        { "data": "failed_records", "orderable": false },
        { "data": "deleted_records", "orderable": false },
        { "data": "total_collection_entries", "orderable": false },
        { "data": "total_work_entries", "orderable": false },
        { "data": "total_file_set_entries", "orderable": false },
        { "data": "actions", "orderable": false }
      ],
      initComplete: function () {
        // Add status filter
        statusSelect.bind(this)()
        // Add refresh link
        refreshLink.bind(this)()
      }
    } );
  }

  if($('#exporters-table').length) {
    $('#exporters-table').DataTable( {
      'processing': true,
      'serverSide': true,
      "ajax": window.location.href.replace(/(\/exporters)/, "$1/exporter_table.json"),
      "pageLength": 30,
      "lengthMenu": [[30, 100, 200], [30, 100, 200]],
      "language": bulkraxDatatableLanguage(),
      "columns": [
        { "data": "name" },
        { "data": "status_message" },
        { "data": "created_at" },
        { "data": "download", "orderable": false },
        { "data": "actions", "orderable": false }
      ],
      initComplete: function () {
        // Add status filter
        statusSelect.bind(this)()
        // Add refresh link
        refreshLink.bind(this)()
      }
    } );
  }

})

function bulkraxDatatableFilters() {
  return (window.BulkraxI18n && window.BulkraxI18n.datatable && window.BulkraxI18n.datatable.filters) || {}
}

function bulkraxDatatableStatuses() {
  return (window.BulkraxI18n && window.BulkraxI18n.datatable && window.BulkraxI18n.datatable.status) || {}
}

function entrySelect() {
  let entrySelect = document.createElement('select')
  entrySelect.id = 'entry-filter'
  entrySelect.classList.value = 'form-control input-sm'
  entrySelect.style.marginRight = '10px'

  var filters = bulkraxDatatableFilters()
  entrySelect.add(new Option(filters.filter_by_entry_class || 'Filter by Entry Class', ''))
  // Read the options from the footer and add them to the entrySelect
  $('#importer-entry-classes').text().split('|').forEach(function (col, i) {
    entrySelect.add(new Option(col.trim()))
  })
  document.querySelector('div#importer-show-table_filter').firstChild.prepend(entrySelect)

  // Apply listener for user change in value
  entrySelect.addEventListener('change', function () {
    var val = entrySelect.value;
    this.api()
      .search(val ? val : '', false, false)
      .draw();
  }.bind(this));
}

function statusSelect() {
  let statusSelect = document.createElement('select');
  statusSelect.id = 'status-filter'
  statusSelect.classList.value = 'form-control input-sm'
  statusSelect.style.marginRight = '10px'

  var filters = bulkraxDatatableFilters()
  var statuses = bulkraxDatatableStatuses()
  statusSelect.add(new Option(filters.filter_by_status || 'Filter by Status', ''));
  // The option value must remain the English status string, as that is what
  // the backend search/filter logic matches against.
  statusSelect.add(new Option(statuses.complete || 'Complete', 'Complete'))
  statusSelect.add(new Option(statuses.pending || 'Pending', 'Pending'))
  statusSelect.add(new Option(statuses.failed || 'Failed', 'Failed'))
  statusSelect.add(new Option(statuses.skipped || 'Skipped', 'Skipped'))
  statusSelect.add(new Option(statuses.deleted || 'Deleted', 'Deleted'))
  statusSelect.add(new Option(statuses.complete_with_failures || 'Complete (with failures)', 'Complete (with failures)'))

  document.querySelector('div.dataTables_filter').firstChild.prepend(statusSelect)

  // Apply listener for user change in value
  statusSelect.addEventListener('change', function () {
    var val = statusSelect.value;
    this.api()
      .search(val ? val : '', false, false)
      .draw();
  }.bind(this));
}

function refreshLink() {
  let refreshLink = document.createElement('a');
  refreshLink.onclick = function() {
    this.api().ajax.reload(null, false)
  }.bind(this)
  refreshLink.classList.value = 'fa fa-refresh'
  refreshLink.style.marginLeft = '10px'
  document.querySelector('div.dataTables_filter').firstChild.append(refreshLink)
}
