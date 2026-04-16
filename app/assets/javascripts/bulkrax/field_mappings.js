(function() {
  'use strict';

  var fieldIndex = 1000;

  function init() {
    var table = document.getElementById('field-mappings-table');
    if (!table) return;

    // Add field button
    var addBtn = document.getElementById('add-field-btn');
    if (addBtn) {
      addBtn.addEventListener('click', addFieldRow);
    }

    // Delegate events on table
    table.addEventListener('click', function(e) {
      var target = e.target.closest('button');
      if (!target) return;

      if (target.classList.contains('expand-toggle')) {
        toggleAdvanced(target);
      } else if (target.classList.contains('remove-field-btn')) {
        removeFieldRow(target);
      }
    });

    // Split checkbox toggle
    table.addEventListener('change', function(e) {
      if (e.target.classList.contains('split-checkbox')) {
        var wrapper = e.target.closest('td').querySelector('.split-regex-wrapper');
        if (wrapper) {
          wrapper.style.display = e.target.checked ? '' : 'none';
        }
      }
    });

    // Regex preview on input
    document.addEventListener('input', function(e) {
      if (e.target.classList.contains('regex-input')) {
        updateRegexPreview(e.target);
      }
    });

    // Initialize regex previews for existing values
    var regexInputs = document.querySelectorAll('.regex-input');
    for (var i = 0; i < regexInputs.length; i++) {
      if (regexInputs[i].value) {
        updateRegexPreview(regexInputs[i]);
      }
    }
  }

  function addFieldRow() {
    var template = document.getElementById('field-row-template');
    if (!template) return;

    var html = template.innerHTML.replace(/__INDEX__/g, fieldIndex++);
    var tbody = document.querySelector('#field-mappings-table tbody');
    tbody.insertAdjacentHTML('beforeend', html);
  }

  function removeFieldRow(button) {
    var row = button.closest('tr.field-row');
    if (!row) return;

    var idx = row.getAttribute('data-index');
    var advancedRow = document.querySelector('tr.advanced-row[data-index="' + idx + '"]');

    row.remove();
    if (advancedRow) advancedRow.remove();
  }

  function toggleAdvanced(button) {
    var row = button.closest('tr.field-row');
    if (!row) return;

    var idx = row.getAttribute('data-index');
    var advancedRow = document.querySelector('tr.advanced-row[data-index="' + idx + '"]');
    if (!advancedRow) return;

    var isVisible = advancedRow.style.display !== 'none';
    advancedRow.style.display = isVisible ? 'none' : '';

    var icon = button.querySelector('.fa');
    if (icon) {
      icon.classList.toggle('fa-chevron-down', isVisible);
      icon.classList.toggle('fa-chevron-up', !isVisible);
    }
  }

  function updateRegexPreview(input) {
    var preview = input.parentElement.querySelector('.regex-preview');
    if (!preview) return;

    var pattern = input.value.trim();
    if (!pattern) {
      preview.textContent = '';
      preview.className = 'regex-preview text-muted';
      return;
    }

    try {
      new RegExp(pattern);
      preview.textContent = describeRegex(pattern);
      preview.className = 'regex-preview text-muted';
    } catch (e) {
      preview.textContent = 'Invalid pattern: ' + e.message;
      preview.className = 'regex-preview text-danger';
    }
  }

  function describeRegex(pattern) {
    // Common Bulkrax mapping patterns
    if (/^\\s\*\[([^\]]+)\]\\s\*$/.test(pattern)) {
      var charMatch = pattern.match(/\[([^\]]+)\]/);
      var chars = charMatch ? charMatch[1] : '';
      return 'Splits on ' + describeLiteral(chars) + ' surrounded by optional whitespace';
    }

    if (/^\\[|]$/.test(pattern) || pattern === '\\|') {
      return 'Splits on literal pipe (|)';
    }

    if (/^\(([^)]+)\)$/.test(pattern)) {
      var alts = pattern.slice(1, -1).split('|');
      return "Matches '" + alts.join("' or '") + "'";
    }

    if (/^[a-zA-Z0-9_ ]+$/.test(pattern)) {
      return "Matches literal '" + pattern + "'";
    }

    return 'Valid regex pattern';
  }

  function describeLiteral(char) {
    var names = { '|': 'pipe (|)', ';': 'semicolon (;)', ',': 'comma (,)', ':': 'colon (:)' };
    return names[char] || "'" + char + "'";
  }

  // Support both Turbolinks and standard page load
  if (typeof Turbolinks !== 'undefined') {
    document.addEventListener('turbolinks:load', init);
  } else if (typeof Turbo !== 'undefined') {
    document.addEventListener('turbo:load', init);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
