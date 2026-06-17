# Refactoring Bulkrax Controllers to Rails/CanCanCan Conventions

## Executive Summary

The `importer-exorter-permissions` branch introduced working ownership-based authorization, but used ad-hoc patterns rather than CanCanCan's established conventions. This plan describes how to replace the custom methods with proper CanCan rules, `load_and_authorize_resource`, and `accessible_by` scoping — making authorization logic centralised, testable, and consistent with the host app's Ability class.

---

## Current Non-Conventional Patterns

### 1. `Bulkrax::Ability` defines no `can` rules

**File:** `app/models/concerns/bulkrax/ability.rb`

The concern exposes four plain Ruby predicate methods (`can_import_works?`, `can_export_works?`, `can_admin_importers?`, `can_admin_exporters?`) and never calls `can` or `cannot`. CanCanCan conventions require that an Ability class define permissions by calling `can :action, Model` inside `initialize` (or a delegated method). Without these declarations, CanCan's `authorize!`, `load_and_authorize_resource`, and `Model.accessible_by(current_ability)` have nothing to evaluate.

### 2. `check_permissions` as a coarse gate

**Files:** `app/controllers/bulkrax/importers_controller.rb:375-377`, `exporters_controller.rb:153-155`, `entries_controller.rb:100-102`, `guided_imports_controller.rb:171-173`

Each controller defines its own private `check_permissions` method that raises `CanCan::AccessDenied` against a boolean predicate. The conventional pattern is `before_action { authorize! :read, Importer }` (or relying on `load_and_authorize_resource` to do this implicitly). The custom gate only checks coarse capability, not per-resource permissions.

### 3. Manual `accessible_importers` / `accessible_exporters` scoping helpers

**File:** `app/controllers/bulkrax/application_controller.rb:12-27`

These methods manually branch on `can_admin_*?` to return either `Model.all` or `Model.where(user_id: current_user.id)`. The conventional CanCan approach is `Model.accessible_by(current_ability, :read)`, which evaluates the rules defined in the Ability class and builds a scope automatically.

### 4. Inline `item_accessible?` guards in action bodies

**File:** `app/controllers/bulkrax/entries_controller.rb:21, 50`

```ruby
raise CanCan::AccessDenied unless item_accessible?(item)
```

The conventional approach is `authorize! :update, item` (or letting `load_and_authorize_resource` call it). Keeping authorization inside action bodies spreads the logic and makes it easy to forget on new actions.

### 5. Unscoped `Entry.find` followed by a parent check

**File:** `app/controllers/bulkrax/entries_controller.rb:19, 48`

```ruby
@entry = Entry.find(params[:id])
item = @entry.importerexporter
raise CanCan::AccessDenied unless item_accessible?(item)
```

This fetches the entry unconditionally, then checks the parent. Any user who knows an entry ID can trigger a DB hit before the authorization guard runs. The conventional pattern is either a scoped find on the parent or `load_and_authorize_resource` with `:through` pointing to the parent resource.

### 6. API bypass hardcoded in `accessible_importers` override

**File:** `app/controllers/bulkrax/importers_controller.rb:258-261`

```ruby
def accessible_importers
  return Importer.all if api_request?
  super
end
```

This silently removes all ownership filtering for API requests. The conventional approach is to authenticate the API token and then express API permissions as regular CanCan rules (e.g., `can :manage, Importer` for service tokens), keeping authorization logic in one place.

### 7. Inconsistent error types

`EntriesController` raises `CanCan::AccessDenied` explicitly, while `ImportersController` and `ExportersController` raise `ActiveRecord::RecordNotFound` implicitly (via `.find` on a scoped relation). This means the error handler a host app configures for one case will not catch the other.

---

## Proposed Conventional Replacements

### Step A — Define `can` rules inside `Bulkrax::Ability`

Convert the four predicate methods into proper CanCan rule declarations. The concern's `included` block (or a `bulkrax_default_abilities` method called from the host app's `initialize`) should emit `can` calls:

```ruby
module Bulkrax
  module Ability
    extend ActiveSupport::Concern

    included do
      # called from initialize in the including Ability class
    end

    def bulkrax_default_abilities
      if can_import_works?
        can :create, Bulkrax::Importer
        can [:read, :update, :destroy], Bulkrax::Importer, user_id: current_user.id
        can :read, Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Importer) &&
            entry.importerexporter.user_id == current_user.id
        end
        can [:update, :destroy], Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Importer) &&
            entry.importerexporter.user_id == current_user.id
        end
      end

      if can_export_works?
        can :create, Bulkrax::Exporter
        can [:read, :update, :destroy], Bulkrax::Exporter, user_id: current_user.id
        can :read, Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Exporter) &&
            entry.importerexporter.user_id == current_user.id
        end
        can [:update, :destroy], Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Exporter) &&
            entry.importerexporter.user_id == current_user.id
        end
      end

      if can_admin_importers?
        can :manage, Bulkrax::Importer
      end

      if can_admin_exporters?
        can :manage, Bulkrax::Exporter
      end
    end
  end
end
```

The host app's Ability class calls `bulkrax_default_abilities` from `initialize` (documented in the concern). The predicates remain as overrideable hooks; the rules are the authoritative permissions.

> **Important:** Block-form `can` rules (the entry rules above) are checked one-at-a-time in Ruby and do not generate SQL — they cannot be used with `accessible_by`. The SQL-hash form `can :action, Model, column: value` does generate scope. We therefore use hash form for Importer/Exporter (owned by `user_id`) and accept block form only for Entry, where authorization is through the parent. See migration risks below.

### Step B — Replace `check_permissions` with `authorize_resource`

In `ImportersController`, `ExportersController`, and `GuidedImportsController`, remove `check_permissions` and add:

```ruby
authorize_resource class: Bulkrax::Importer  # or Exporter
```

`authorize_resource` calls `authorize! :action, Model` for the appropriate action (using Rails' standard action-to-CRUD mapping) without loading the record. Alternatively, use `load_and_authorize_resource` (see Step C).

For `EntriesController`, the dual-parent structure (entries under both importers and exporters) makes plain `authorize_resource` awkward. Use an explicit `before_action :authorize_entry_action!` that calls `authorize! action, @entry` after the entry is loaded.

### Step C — Replace manual `set_importer`/`set_exporter` with `load_and_authorize_resource`

```ruby
# ImportersController
load_and_authorize_resource class: Bulkrax::Importer,
                            instance_name: :importer,
                            except: [:index, :importer_table, :sample_csv_file, :external_sets]
```

This replaces the `set_importer` before_action and the per-action `accessible_importers.find(id)` calls with a single declaration. For collection actions (`index`, `importer_table`) use `accessible_by` explicitly (Step D).

For `ExportersController`:

```ruby
load_and_authorize_resource class: Bulkrax::Exporter,
                            instance_name: :exporter,
                            except: [:index, :exporter_table]
```

For `EntriesController`, use nested resource loading:

```ruby
load_and_authorize_resource :importer, class: Bulkrax::Importer,
                            only: [:show], id_param: :importer_id
load_and_authorize_resource :exporter, class: Bulkrax::Exporter,
                            only: [:show], id_param: :exporter_id
load_and_authorize_resource :entry, class: Bulkrax::Entry,
                            through: [:importer, :exporter],
                            through_association: :entries,
                            only: [:show]
# update and destroy load entry independently then authorize
before_action :load_and_authorize_entry!, only: [:update, :destroy]
```

### Step D — Replace `accessible_importers`/`accessible_exporters` with `accessible_by`

```ruby
# Instead of:
@importers = accessible_importers.order(...)

# Use:
@importers = Bulkrax::Importer.accessible_by(current_ability).order(...)
```

`accessible_by` works for hash-form rules (SQL-generatable). Because the `can :read, Importer, user_id: current_user.id` and `can :manage, Importer` (admin) rules are both hash-form, they produce a correct `WHERE` clause automatically. Remove `accessible_importers`, `accessible_exporters`, and `item_accessible?` from `ApplicationController` once all call sites are migrated.

### Step E — Address the API authorization bypass

The `accessible_importers` override in `ImportersController` exists because API clients are authenticated by token, not session, and no user-level scoping was implemented for them. Conventional options:

1. **Preferred:** Authenticate the token, resolve it to a `current_user`, and let normal CanCan rules apply. If the token represents a service account that should see all importers, express that as `can :manage, Bulkrax::Importer` in the service account's Ability.
2. **Fallback:** Keep the override but move it to a dedicated `ApiImportersController` so the bypass is an explicit, documented decision rather than a hidden branch inside the shared controller.

Until option 1 is fully implemented, document the bypass with a `# TODO:` comment and a reference to a tracking issue rather than leaving it as silent code.

### Step F — Standardise error handling

Settle on one error type for "you don't have permission to see this resource." The Rails/CanCan convention is `CanCan::AccessDenied`, rescued in `ApplicationController`:

```ruby
rescue_from CanCan::AccessDenied do |exception|
  respond_to do |format|
    format.html { redirect_to main_app.root_path, alert: exception.message }
    format.json { render json: { error: exception.message }, status: :forbidden }
  end
end
```

Scoped `.find` currently converts "not found or not owned" into `ActiveRecord::RecordNotFound` (HTTP 404), while explicit raises give HTTP 403. These have different UX and security implications. Choose one consistently:
- **403 everywhere** (recommended for API): always raise `CanCan::AccessDenied`.
- **404 for non-owners** (security-through-obscurity, common in Hyrax): keep scoped `.find` but only for HTML actions; API actions raise 403.

Whichever is chosen, enforce it in `ApplicationController` and remove duplicate rescue blocks from individual controllers.

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/models/concerns/bulkrax/ability.rb` | Add `bulkrax_default_abilities` with `can` rule declarations; keep predicates as hooks |
| `app/controllers/bulkrax/application_controller.rb` | Add `rescue_from CanCan::AccessDenied`; remove `accessible_importers`, `accessible_exporters`, `item_accessible?` (after migration) |
| `app/controllers/bulkrax/importers_controller.rb` | Replace `check_permissions` + `set_importer` with `load_and_authorize_resource`; replace `accessible_importers.find/order` with `accessible_by`; document/extract API bypass |
| `app/controllers/bulkrax/exporters_controller.rb` | Replace `check_permissions` + `set_exporter` with `load_and_authorize_resource`; replace `accessible_exporters` calls with `accessible_by` |
| `app/controllers/bulkrax/entries_controller.rb` | Replace manual `Entry.find` + `item_accessible?` with `load_and_authorize_resource` (through parent) + `authorize!` |
| `app/controllers/bulkrax/guided_imports_controller.rb` | Replace `check_permissions` with `authorize_resource` |
| `app/controllers/concerns/bulkrax/datatables_behavior.rb` | Replace `accessible_importers`/`accessible_exporters` calls with `accessible_by` |
| `spec/test_app/app/models/ability.rb` | Call `bulkrax_default_abilities` from `initialize` |
| `spec/models/concerns/bulkrax/ability_spec.rb` | Add specs for generated `can` rules and `accessible_by` scoping |
| `spec/controllers/bulkrax/importers_controller_spec.rb` | Update ownership enforcement contexts; add API authorization tests |
| `spec/controllers/bulkrax/exporters_controller_spec.rb` | Same updates as importers |
| `spec/controllers/bulkrax/entries_controller_spec.rb` | Add specs for unauthorized parent access to entry |

---

## Testing Strategy

### Unit tests — `Bulkrax::Ability`

Test each `can` rule in isolation using CanCan's `be_able_to` matcher:

```ruby
it { is_expected.to be_able_to(:create, Bulkrax::Importer) }
it { is_expected.to be_able_to(:read, owned_importer) }
it { is_expected.not_to be_able_to(:read, other_users_importer) }
it { is_expected.to be_able_to(:manage, any_importer) }  # admin
```

These run without a controller or HTTP request, making them fast and precise. Cover the cross-product of (user role) × (model) × (action).

### Controller specs — authentication & authorization together

Keep the existing controller spec structure but replace the bespoke "ownership enforcement" context blocks with shared examples that exercise CanCan's `current_ability`:

```ruby
shared_examples 'a resource requiring ownership or admin' do |action, params_proc|
  context 'when current_user does not own the resource' do
    it 'raises CanCan::AccessDenied (or returns 404)' ...
  end
  context 'when current_user owns the resource' do
    it 'succeeds' ...
  end
  context 'when current_user is admin' do
    it 'succeeds' ...
  end
end
```

Apply to `show`, `edit`, `update`, `destroy` on importers, exporters, and entries.

### Collection action specs

Add tests that `importer_table` and `exporter_table` return only records owned by the current user (not others'), and return all records for admin users.

### API authorization specs (new, currently missing)

Test that API token requests respect user scoping when a `current_user` can be resolved, and that unresolved tokens receive HTTP 401/403.

### Integration/request specs

Where possible, add a request spec that performs the full stack (routes → controller → CanCan → model) to catch any misconfiguration in `load_and_authorize_resource` that unit tests might miss.

---

## Migration Risks

### 1. Block-form `can` rules do not generate SQL scopes

Block-form rules (required for `Entry` because authorization depends on the parent association) cannot be used with `accessible_by`. Any call to `Entry.accessible_by(current_ability)` will raise a `CanCan::Error` or silently fall back to fetching all records. **Mitigation:** For `Entry` collections, always scope through the parent: `@importer.entries` (already owned) rather than `Entry.accessible_by(...)`.

### 2. `load_and_authorize_resource` param naming

`load_and_authorize_resource` infers the record from `params[:id]` and the class from the controller name. In Bulkrax, some actions use `params[:importer_id]` instead of `params[:id]` (e.g., `continue`, `export_errors`). Use the `id_param:` option or keep manual `before_action` for those actions.

### 3. Host app `Ability` classes must opt in to new rules

Adding `bulkrax_default_abilities` is a new public API. Host apps that include `Bulkrax::Ability` but do not call `bulkrax_default_abilities` from their `initialize` will get **no** Bulkrax-specific rules, meaning all actions will be denied. This is a breaking change for host apps. Document clearly in the CHANGELOG and upgrade notes. Consider calling `bulkrax_default_abilities` automatically from an `included` block with a deprecation warning if it has not been called, or provide a configuration flag.

### 4. API consumer backward compatibility

Removing the `accessible_importers` override in `ImportersController` will immediately break API clients that rely on seeing all importers regardless of ownership. This must be addressed before removing the override — either by a service-account CanCan rule or by keeping the override in a separate controller.

### 5. `rescue_from` placement in engines

Engines should define `rescue_from` only in their own base controller (`Bulkrax::ApplicationController`), not in host app controllers. Test that the handler does not shadow host app error pages.

### 6. `load_and_authorize_resource` and STI

`Entry` uses single-table inheritance. `load_and_authorize_resource class: Bulkrax::Entry` will load any Entry subclass record from `params[:id]` but authorize it against the `Bulkrax::Entry` class. Verify that `can :update, Bulkrax::Entry` rules match STI subclasses correctly; add explicit rules for subclass types if needed.

---

## Implementation Tasks

These are ordered by dependency. Each task is small enough to review independently.

1. **[Ability] Define `bulkrax_default_abilities`** — Add `can` rule declarations to `Bulkrax::Ability`; add unit specs proving each rule works for owner, non-owner, and admin. Keep predicates intact.

2. **[Test App] Wire `bulkrax_default_abilities`** — Update `spec/test_app/app/models/ability.rb` to call `bulkrax_default_abilities` from `initialize`; confirm existing specs still pass.

3. **[ApplicationController] Add `rescue_from`** — Add `rescue_from CanCan::AccessDenied` with HTML/JSON responses; add a shared example to controller specs asserting the correct HTTP status.

4. **[ExportersController] Migrate to `load_and_authorize_resource`** — Replace `check_permissions` and `set_exporter` with `load_and_authorize_resource`; replace `accessible_exporters` calls with `Exporter.accessible_by(current_ability)`. ExportersController is simpler (no API path) so migrate it first to validate the approach.

5. **[ImportersController] Migrate to `load_and_authorize_resource`** — Same as exporters. Extract the API bypass into a separate method or dedicated controller. Handle `id_param:` for `continue`, `export_errors`, `upload_corrected_entries*` actions.

6. **[EntriesController] Migrate to authorized nested loading** — Replace unscoped `Entry.find` + `item_accessible?` with `load_and_authorize_resource :through`. Verify block-form `can` rules match.

7. **[GuidedImportsController] Replace `check_permissions`** — Swap for `authorize_resource class: Bulkrax::Importer` (or `before_action { authorize! :create, Bulkrax::Importer }`).

8. **[DatatablesBehavior] Replace `accessible_*` helpers** — Swap remaining `accessible_importers`/`accessible_exporters` calls in the concern with `accessible_by`.

9. **[ApplicationController] Remove dead helpers** — Once all call sites are migrated, delete `accessible_importers`, `accessible_exporters`, and `item_accessible?`.

10. **[Specs] Fill coverage gaps** — Add collection-action ownership specs, API authorization specs, and at least one integration/request spec per resource.

11. **[Docs] Update CHANGELOG and upgrade guide** — Document `bulkrax_default_abilities` as a new required call, the standardised error type, and any changes to API behavior.
