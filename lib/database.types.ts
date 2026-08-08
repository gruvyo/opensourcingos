export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          after_data: Json | null
          before_data: Json | null
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          organization_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          organization_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      award_lines: {
        Row: {
          annualized_award_amount: number | null
          award_id: string | null
          awarded_extended_amount: number | null
          awarded_one_time_amount: number | null
          awarded_quantity: number | null
          awarded_recurring_amount: number | null
          awarded_term_months: number | null
          awarded_unit_price: number | null
          created_at: string | null
          event_id: string | null
          id: string
          line_number: number
          organization_id: string | null
          scope_line_id: string | null
          updated_at: string | null
        }
        Insert: {
          annualized_award_amount?: number | null
          award_id?: string | null
          awarded_extended_amount?: number | null
          awarded_one_time_amount?: number | null
          awarded_quantity?: number | null
          awarded_recurring_amount?: number | null
          awarded_term_months?: number | null
          awarded_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          id?: string
          line_number: number
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Update: {
          annualized_award_amount?: number | null
          award_id?: string | null
          awarded_extended_amount?: number | null
          awarded_one_time_amount?: number | null
          awarded_quantity?: number | null
          awarded_recurring_amount?: number | null
          awarded_term_months?: number | null
          awarded_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          id?: string
          line_number?: number
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "award_lines_award_id_fkey"
            columns: ["award_id"]
            isOneToOne: false
            referencedRelation: "awards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "award_lines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "award_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "award_lines_scope_line_id_fkey"
            columns: ["scope_line_id"]
            isOneToOne: false
            referencedRelation: "event_scope_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      awards: {
        Row: {
          award_approval_date: string | null
          award_approved_by: string | null
          award_date: string | null
          award_name: string
          award_notes: string | null
          award_status: string | null
          award_total_amount: number | null
          created_at: string | null
          created_by: string | null
          event_id: string | null
          id: string
          offer_id: string | null
          organization_id: string | null
          supplier_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          award_approval_date?: string | null
          award_approved_by?: string | null
          award_date?: string | null
          award_name: string
          award_notes?: string | null
          award_status?: string | null
          award_total_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          id?: string
          offer_id?: string | null
          organization_id?: string | null
          supplier_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          award_approval_date?: string | null
          award_approved_by?: string | null
          award_date?: string | null
          award_name?: string
          award_notes?: string | null
          award_status?: string | null
          award_total_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          id?: string
          offer_id?: string | null
          organization_id?: string | null
          supplier_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "awards_award_approved_by_fkey"
            columns: ["award_approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_offer_id_fkey"
            columns: ["offer_id"]
            isOneToOne: false
            referencedRelation: "supplier_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "awards_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      baseline_lines: {
        Row: {
          annualized_baseline_amount: number | null
          baseline_extended_amount: number | null
          baseline_id: string | null
          baseline_one_time_amount: number | null
          baseline_quantity: number | null
          baseline_recurring_amount: number | null
          baseline_term_months: number | null
          baseline_unit_price: number | null
          created_at: string | null
          event_id: string | null
          freight_amount_included: number | null
          id: string
          line_number: number
          normalized_extended_amount: number | null
          normalized_quantity: number | null
          normalized_unit_price: number | null
          notes: string | null
          organization_id: string | null
          scope_line_id: string | null
          source_document_id: string | null
          tax_amount_included: number | null
          updated_at: string | null
        }
        Insert: {
          annualized_baseline_amount?: number | null
          baseline_extended_amount?: number | null
          baseline_id?: string | null
          baseline_one_time_amount?: number | null
          baseline_quantity?: number | null
          baseline_recurring_amount?: number | null
          baseline_term_months?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          freight_amount_included?: number | null
          id?: string
          line_number: number
          normalized_extended_amount?: number | null
          normalized_quantity?: number | null
          normalized_unit_price?: number | null
          notes?: string | null
          organization_id?: string | null
          scope_line_id?: string | null
          source_document_id?: string | null
          tax_amount_included?: number | null
          updated_at?: string | null
        }
        Update: {
          annualized_baseline_amount?: number | null
          baseline_extended_amount?: number | null
          baseline_id?: string | null
          baseline_one_time_amount?: number | null
          baseline_quantity?: number | null
          baseline_recurring_amount?: number | null
          baseline_term_months?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          freight_amount_included?: number | null
          id?: string
          line_number?: number
          normalized_extended_amount?: number | null
          normalized_quantity?: number | null
          normalized_unit_price?: number | null
          notes?: string | null
          organization_id?: string | null
          scope_line_id?: string | null
          source_document_id?: string | null
          tax_amount_included?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "baseline_lines_baseline_id_fkey"
            columns: ["baseline_id"]
            isOneToOne: false
            referencedRelation: "baselines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baseline_lines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baseline_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baseline_lines_scope_line_id_fkey"
            columns: ["scope_line_id"]
            isOneToOne: false
            referencedRelation: "event_scope_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      baselines: {
        Row: {
          baseline_approval_date: string | null
          baseline_approved_by: string | null
          baseline_currency_code: string | null
          baseline_fx_rate_to_usd: number | null
          baseline_lock_date: string | null
          baseline_lock_status: string | null
          baseline_name: string
          baseline_normalized_amount: number | null
          baseline_period_end: string | null
          baseline_period_start: string | null
          baseline_source: string | null
          baseline_term_months: number | null
          baseline_total_amount: number | null
          baseline_type: string
          created_at: string | null
          created_by: string | null
          event_id: string | null
          hard_reduction_override: boolean
          hard_reduction_override_at: string | null
          hard_reduction_override_by: string | null
          hard_reduction_override_reason: string | null
          id: string
          is_selected: boolean
          normalization_notes: string | null
          official_for_cost_avoidance: boolean | null
          official_for_demand_reduction: boolean | null
          official_for_hard_savings: boolean | null
          organization_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          baseline_approval_date?: string | null
          baseline_approved_by?: string | null
          baseline_currency_code?: string | null
          baseline_fx_rate_to_usd?: number | null
          baseline_lock_date?: string | null
          baseline_lock_status?: string | null
          baseline_name: string
          baseline_normalized_amount?: number | null
          baseline_period_end?: string | null
          baseline_period_start?: string | null
          baseline_source?: string | null
          baseline_term_months?: number | null
          baseline_total_amount?: number | null
          baseline_type: string
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          hard_reduction_override?: boolean
          hard_reduction_override_at?: string | null
          hard_reduction_override_by?: string | null
          hard_reduction_override_reason?: string | null
          id?: string
          is_selected?: boolean
          normalization_notes?: string | null
          official_for_cost_avoidance?: boolean | null
          official_for_demand_reduction?: boolean | null
          official_for_hard_savings?: boolean | null
          organization_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          baseline_approval_date?: string | null
          baseline_approved_by?: string | null
          baseline_currency_code?: string | null
          baseline_fx_rate_to_usd?: number | null
          baseline_lock_date?: string | null
          baseline_lock_status?: string | null
          baseline_name?: string
          baseline_normalized_amount?: number | null
          baseline_period_end?: string | null
          baseline_period_start?: string | null
          baseline_source?: string | null
          baseline_term_months?: number | null
          baseline_total_amount?: number | null
          baseline_type?: string
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          hard_reduction_override?: boolean
          hard_reduction_override_at?: string | null
          hard_reduction_override_by?: string | null
          hard_reduction_override_reason?: string | null
          id?: string
          is_selected?: boolean
          normalization_notes?: string | null
          official_for_cost_avoidance?: boolean | null
          official_for_demand_reduction?: boolean | null
          official_for_hard_savings?: boolean | null
          organization_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "baselines_baseline_approved_by_fkey"
            columns: ["baseline_approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baselines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baselines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baselines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "baselines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      business_units: {
        Row: {
          active_flag: boolean
          business_unit_name: string
          created_at: string | null
          id: string
          organization_id: string | null
          parent_business_unit_id: string | null
        }
        Insert: {
          active_flag?: boolean
          business_unit_name: string
          created_at?: string | null
          id?: string
          organization_id?: string | null
          parent_business_unit_id?: string | null
        }
        Update: {
          active_flag?: boolean
          business_unit_name?: string
          created_at?: string | null
          id?: string
          organization_id?: string | null
          parent_business_unit_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "business_units_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_units_parent_business_unit_id_fkey"
            columns: ["parent_business_unit_id"]
            isOneToOne: false
            referencedRelation: "business_units"
            referencedColumns: ["id"]
          },
        ]
      }
      categories: {
        Row: {
          active_flag: boolean
          category_name: string
          created_at: string | null
          default_baseline_type: string | null
          id: string
          organization_id: string | null
          parent_category_id: string | null
        }
        Insert: {
          active_flag?: boolean
          category_name: string
          created_at?: string | null
          default_baseline_type?: string | null
          id?: string
          organization_id?: string | null
          parent_category_id?: string | null
        }
        Update: {
          active_flag?: boolean
          category_name?: string
          created_at?: string | null
          default_baseline_type?: string | null
          id?: string
          organization_id?: string | null
          parent_category_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "categories_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "categories_parent_category_id_fkey"
            columns: ["parent_category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
        ]
      }
      cost_centers: {
        Row: {
          active_flag: boolean
          business_unit_id: string | null
          cost_center_name: string
          created_at: string | null
          gl_account_default: string | null
          id: string
          organization_id: string | null
        }
        Insert: {
          active_flag?: boolean
          business_unit_id?: string | null
          cost_center_name: string
          created_at?: string | null
          gl_account_default?: string | null
          id?: string
          organization_id?: string | null
        }
        Update: {
          active_flag?: boolean
          business_unit_id?: string | null
          cost_center_name?: string
          created_at?: string | null
          gl_account_default?: string | null
          id?: string
          organization_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cost_centers_business_unit_id_fkey"
            columns: ["business_unit_id"]
            isOneToOne: false
            referencedRelation: "business_units"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_centers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      event_scope_lines: {
        Row: {
          baseline_quantity: number | null
          business_equivalency_confirmed: boolean | null
          business_equivalency_confirmed_by: string | null
          category_id: string | null
          created_at: string | null
          event_id: string | null
          final_quantity: number | null
          forecast_quantity: number | null
          id: string
          item_description: string | null
          item_service_name: string
          line_number: number
          location_id: string | null
          organization_id: string | null
          scope_change_description: string | null
          scope_change_flag: boolean | null
          uom: string | null
          updated_at: string | null
        }
        Insert: {
          baseline_quantity?: number | null
          business_equivalency_confirmed?: boolean | null
          business_equivalency_confirmed_by?: string | null
          category_id?: string | null
          created_at?: string | null
          event_id?: string | null
          final_quantity?: number | null
          forecast_quantity?: number | null
          id?: string
          item_description?: string | null
          item_service_name: string
          line_number: number
          location_id?: string | null
          organization_id?: string | null
          scope_change_description?: string | null
          scope_change_flag?: boolean | null
          uom?: string | null
          updated_at?: string | null
        }
        Update: {
          baseline_quantity?: number | null
          business_equivalency_confirmed?: boolean | null
          business_equivalency_confirmed_by?: string | null
          category_id?: string | null
          created_at?: string | null
          event_id?: string | null
          final_quantity?: number | null
          forecast_quantity?: number | null
          id?: string
          item_description?: string | null
          item_service_name?: string
          line_number?: number
          location_id?: string | null
          organization_id?: string | null
          scope_change_description?: string | null
          scope_change_flag?: boolean | null
          uom?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_scope_lines_business_equivalency_confirmed_by_fkey"
            columns: ["business_equivalency_confirmed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_scope_lines_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_scope_lines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_scope_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings: {
        Row: {
          created_at: string
          currency_code: string
          date_format: string
          default_recognition_method: string
          fiscal_year_start_month: number
          hard_reduction_approval_threshold: number | null
          locale: string
          organization_id: string
          project_business_units_enabled: boolean
          project_categories_enabled: boolean
          project_cost_centers_enabled: boolean
          project_descriptions_enabled: boolean
          project_owners_enabled: boolean
          project_updates_enabled: boolean
          require_baseline_for_hard_reduction: boolean
          support_projects_enabled: boolean
          timezone: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          currency_code?: string
          date_format?: string
          default_recognition_method?: string
          fiscal_year_start_month?: number
          hard_reduction_approval_threshold?: number | null
          locale?: string
          organization_id: string
          project_business_units_enabled?: boolean
          project_categories_enabled?: boolean
          project_cost_centers_enabled?: boolean
          project_descriptions_enabled?: boolean
          project_owners_enabled?: boolean
          project_updates_enabled?: boolean
          require_baseline_for_hard_reduction?: boolean
          support_projects_enabled?: boolean
          timezone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          currency_code?: string
          date_format?: string
          default_recognition_method?: string
          fiscal_year_start_month?: number
          hard_reduction_approval_threshold?: number | null
          locale?: string
          organization_id?: string
          project_business_units_enabled?: boolean
          project_categories_enabled?: boolean
          project_cost_centers_enabled?: boolean
          project_descriptions_enabled?: boolean
          project_owners_enabled?: boolean
          project_updates_enabled?: boolean
          require_baseline_for_hard_reduction?: boolean
          support_projects_enabled?: boolean
          timezone?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string | null
          id: string
          is_demo_template: boolean
          name: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          is_demo_template?: boolean
          name: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          is_demo_template?: boolean
          name?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string | null
          email: string | null
          full_name: string | null
          id: string
          organization_id: string | null
          role: string | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id: string
          organization_id?: string | null
          role?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id?: string
          organization_id?: string | null
          role?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      project_choice_options: {
        Row: {
          active_flag: boolean
          choice_type: string
          created_at: string
          created_by: string | null
          id: string
          label: string
          organization_id: string
          project_type: string | null
          sort_order: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          active_flag?: boolean
          choice_type: string
          created_at?: string
          created_by?: string | null
          id?: string
          label: string
          organization_id: string
          project_type?: string | null
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          active_flag?: boolean
          choice_type?: string
          created_at?: string
          created_by?: string | null
          id?: string
          label?: string
          organization_id?: string
          project_type?: string | null
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "project_choice_options_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_choice_options_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_choice_options_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      project_updates: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          event_id: string
          id: string
          organization_id: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          event_id: string
          id?: string
          organization_id: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          event_id?: string
          id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_updates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_updates_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_updates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      realization_periods: {
        Row: {
          actual_amount: number | null
          baseline_amount: number | null
          created_at: string | null
          created_by: string | null
          event_id: string | null
          evidence_document_id: string | null
          finance_validated: boolean | null
          finance_validated_by: string | null
          finance_validation_date: string | null
          id: string
          leakage_amount: number | null
          leakage_reason: string | null
          notes: string | null
          organization_id: string | null
          period_end_date: string
          period_name: string
          period_start_date: string
          projected_savings: number | null
          realization_status: string | null
          realized_savings: number | null
          savings_calculation_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          actual_amount?: number | null
          baseline_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          evidence_document_id?: string | null
          finance_validated?: boolean | null
          finance_validated_by?: string | null
          finance_validation_date?: string | null
          id?: string
          leakage_amount?: number | null
          leakage_reason?: string | null
          notes?: string | null
          organization_id?: string | null
          period_end_date: string
          period_name: string
          period_start_date: string
          projected_savings?: number | null
          realization_status?: string | null
          realized_savings?: number | null
          savings_calculation_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          actual_amount?: number | null
          baseline_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          evidence_document_id?: string | null
          finance_validated?: boolean | null
          finance_validated_by?: string | null
          finance_validation_date?: string | null
          id?: string
          leakage_amount?: number | null
          leakage_reason?: string | null
          notes?: string | null
          organization_id?: string | null
          period_end_date?: string
          period_name?: string
          period_start_date?: string
          projected_savings?: number | null
          realization_status?: string | null
          realized_savings?: number | null
          savings_calculation_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "realization_periods_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realization_periods_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realization_periods_finance_validated_by_fkey"
            columns: ["finance_validated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realization_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realization_periods_savings_calculation_id_fkey"
            columns: ["savings_calculation_id"]
            isOneToOne: false
            referencedRelation: "savings_calculations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realization_periods_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      savings_calculation_lines: {
        Row: {
          awarded_extended_amount: number | null
          awarded_quantity: number | null
          awarded_unit_price: number | null
          baseline_extended_amount: number | null
          baseline_quantity: number | null
          baseline_unit_price: number | null
          created_at: string | null
          event_id: string | null
          id: string
          line_number: number
          organization_id: string | null
          savings_amount: number | null
          savings_calculation_id: string | null
          savings_percentage: number | null
          savings_type: string | null
          scope_line_id: string | null
          updated_at: string | null
        }
        Insert: {
          awarded_extended_amount?: number | null
          awarded_quantity?: number | null
          awarded_unit_price?: number | null
          baseline_extended_amount?: number | null
          baseline_quantity?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          id?: string
          line_number: number
          organization_id?: string | null
          savings_amount?: number | null
          savings_calculation_id?: string | null
          savings_percentage?: number | null
          savings_type?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Update: {
          awarded_extended_amount?: number | null
          awarded_quantity?: number | null
          awarded_unit_price?: number | null
          baseline_extended_amount?: number | null
          baseline_quantity?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          event_id?: string | null
          id?: string
          line_number?: number
          organization_id?: string | null
          savings_amount?: number | null
          savings_calculation_id?: string | null
          savings_percentage?: number | null
          savings_type?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "savings_calculation_lines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculation_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculation_lines_savings_calculation_id_fkey"
            columns: ["savings_calculation_id"]
            isOneToOne: false
            referencedRelation: "savings_calculations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculation_lines_scope_line_id_fkey"
            columns: ["scope_line_id"]
            isOneToOne: false
            referencedRelation: "event_scope_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      savings_calculations: {
        Row: {
          award_id: string | null
          award_total_amount: number | null
          baseline_id: string | null
          baseline_total_amount: number | null
          calculation_name: string
          calculation_status: string | null
          cost_avoidance_amount: number | null
          cost_reduction_amount: number | null
          created_at: string | null
          created_by: string | null
          event_id: string | null
          gross_savings_amount: number | null
          id: string
          net_savings_amount: number | null
          opening_proposal_amount: number | null
          organization_id: string | null
          recognition_notes: string | null
          savings_end_date: string | null
          savings_percentage: number | null
          savings_start_date: string | null
          savings_type: string
          schedule_period_count: number | null
          schedule_period_type: string | null
          schedule_start_month: number | null
          schedule_start_year: number | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          award_id?: string | null
          award_total_amount?: number | null
          baseline_id?: string | null
          baseline_total_amount?: number | null
          calculation_name: string
          calculation_status?: string | null
          cost_avoidance_amount?: number | null
          cost_reduction_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          gross_savings_amount?: number | null
          id?: string
          net_savings_amount?: number | null
          opening_proposal_amount?: number | null
          organization_id?: string | null
          recognition_notes?: string | null
          savings_end_date?: string | null
          savings_percentage?: number | null
          savings_start_date?: string | null
          savings_type: string
          schedule_period_count?: number | null
          schedule_period_type?: string | null
          schedule_start_month?: number | null
          schedule_start_year?: number | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          award_id?: string | null
          award_total_amount?: number | null
          baseline_id?: string | null
          baseline_total_amount?: number | null
          calculation_name?: string
          calculation_status?: string | null
          cost_avoidance_amount?: number | null
          cost_reduction_amount?: number | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          gross_savings_amount?: number | null
          id?: string
          net_savings_amount?: number | null
          opening_proposal_amount?: number | null
          organization_id?: string | null
          recognition_notes?: string | null
          savings_end_date?: string | null
          savings_percentage?: number | null
          savings_start_date?: string | null
          savings_type?: string
          schedule_period_count?: number | null
          schedule_period_type?: string | null
          schedule_start_month?: number | null
          schedule_start_year?: number | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "savings_calculations_award_id_fkey"
            columns: ["award_id"]
            isOneToOne: false
            referencedRelation: "awards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculations_baseline_id_fkey"
            columns: ["baseline_id"]
            isOneToOne: false
            referencedRelation: "baselines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculations_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_calculations_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      savings_periods: {
        Row: {
          baseline_amount: number | null
          cost_avoidance_amount: number
          cost_reduction_amount: number | null
          created_at: string
          created_by: string | null
          event_id: string
          final_amount: number
          id: string
          is_edited: boolean
          notes: string | null
          opening_amount: number | null
          organization_id: string
          period_month: number
          period_months: number
          period_number: number
          period_year: number
          savings_calculation_id: string
          total_savings_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          baseline_amount?: number | null
          cost_avoidance_amount?: number
          cost_reduction_amount?: number | null
          created_at?: string
          created_by?: string | null
          event_id: string
          final_amount?: number
          id?: string
          is_edited?: boolean
          notes?: string | null
          opening_amount?: number | null
          organization_id: string
          period_month: number
          period_months?: number
          period_number: number
          period_year: number
          savings_calculation_id: string
          total_savings_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          baseline_amount?: number | null
          cost_avoidance_amount?: number
          cost_reduction_amount?: number | null
          created_at?: string
          created_by?: string | null
          event_id?: string
          final_amount?: number
          id?: string
          is_edited?: boolean
          notes?: string | null
          opening_amount?: number | null
          organization_id?: string
          period_month?: number
          period_months?: number
          period_number?: number
          period_year?: number
          savings_calculation_id?: string
          total_savings_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "savings_periods_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "savings_periods_savings_calculation_id_fkey"
            columns: ["savings_calculation_id"]
            isOneToOne: false
            referencedRelation: "savings_calculations"
            referencedColumns: ["id"]
          },
        ]
      }
      sourcing_events: {
        Row: {
          awarded_supplier_id: string | null
          business_owner_id: string | null
          business_unit_id: string | null
          buyer_name: string | null
          category_id: string | null
          contract_end_date: string | null
          contract_start_date: string | null
          cost_center_id: string | null
          created_at: string | null
          created_by: string | null
          currency_code: string | null
          event_close_date: string | null
          event_description: string | null
          event_name: string
          event_start_date: string | null
          event_status: string | null
          event_type: string
          finance_owner_id: string | null
          fx_rate_to_usd: number | null
          id: string
          incumbent_supplier_id: string | null
          notes: string | null
          official_reporting_basis: string | null
          organization_id: string | null
          procurement_owner_id: string | null
          project_due_date: string | null
          project_type: string | null
          recognition_end_date: string | null
          recognition_start_date: string | null
          sourcing_method: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          awarded_supplier_id?: string | null
          business_owner_id?: string | null
          business_unit_id?: string | null
          buyer_name?: string | null
          category_id?: string | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          cost_center_id?: string | null
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          event_close_date?: string | null
          event_description?: string | null
          event_name: string
          event_start_date?: string | null
          event_status?: string | null
          event_type: string
          finance_owner_id?: string | null
          fx_rate_to_usd?: number | null
          id?: string
          incumbent_supplier_id?: string | null
          notes?: string | null
          official_reporting_basis?: string | null
          organization_id?: string | null
          procurement_owner_id?: string | null
          project_due_date?: string | null
          project_type?: string | null
          recognition_end_date?: string | null
          recognition_start_date?: string | null
          sourcing_method?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          awarded_supplier_id?: string | null
          business_owner_id?: string | null
          business_unit_id?: string | null
          buyer_name?: string | null
          category_id?: string | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          cost_center_id?: string | null
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          event_close_date?: string | null
          event_description?: string | null
          event_name?: string
          event_start_date?: string | null
          event_status?: string | null
          event_type?: string
          finance_owner_id?: string | null
          fx_rate_to_usd?: number | null
          id?: string
          incumbent_supplier_id?: string | null
          notes?: string | null
          official_reporting_basis?: string | null
          organization_id?: string | null
          procurement_owner_id?: string | null
          project_due_date?: string | null
          project_type?: string | null
          recognition_end_date?: string | null
          recognition_start_date?: string | null
          sourcing_method?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sourcing_events_awarded_supplier_id_fkey"
            columns: ["awarded_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_business_owner_id_fkey"
            columns: ["business_owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_business_unit_id_fkey"
            columns: ["business_unit_id"]
            isOneToOne: false
            referencedRelation: "business_units"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_finance_owner_id_fkey"
            columns: ["finance_owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_incumbent_supplier_id_fkey"
            columns: ["incumbent_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_procurement_owner_id_fkey"
            columns: ["procurement_owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sourcing_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_offer_lines: {
        Row: {
          annualized_offer_amount: number | null
          compliance_status: string | null
          created_at: string | null
          event_id: string | null
          exclusion_notes: string | null
          id: string
          line_number: number
          offer_extended_amount: number | null
          offer_id: string | null
          offer_one_time_amount: number | null
          offer_quantity: number | null
          offer_recurring_amount: number | null
          offer_term_months: number | null
          offer_unit_price: number | null
          organization_id: string | null
          scope_line_id: string | null
          updated_at: string | null
        }
        Insert: {
          annualized_offer_amount?: number | null
          compliance_status?: string | null
          created_at?: string | null
          event_id?: string | null
          exclusion_notes?: string | null
          id?: string
          line_number: number
          offer_extended_amount?: number | null
          offer_id?: string | null
          offer_one_time_amount?: number | null
          offer_quantity?: number | null
          offer_recurring_amount?: number | null
          offer_term_months?: number | null
          offer_unit_price?: number | null
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Update: {
          annualized_offer_amount?: number | null
          compliance_status?: string | null
          created_at?: string | null
          event_id?: string | null
          exclusion_notes?: string | null
          id?: string
          line_number?: number
          offer_extended_amount?: number | null
          offer_id?: string | null
          offer_one_time_amount?: number | null
          offer_quantity?: number | null
          offer_recurring_amount?: number | null
          offer_term_months?: number | null
          offer_unit_price?: number | null
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_offer_lines_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offer_lines_offer_id_fkey"
            columns: ["offer_id"]
            isOneToOne: false
            referencedRelation: "supplier_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offer_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offer_lines_scope_line_id_fkey"
            columns: ["scope_line_id"]
            isOneToOne: false
            referencedRelation: "event_scope_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_offers: {
        Row: {
          compliant_bid_flag: boolean | null
          created_at: string | null
          created_by: string | null
          event_id: string | null
          fx_rate_to_usd: number | null
          id: string
          notes: string | null
          offer_currency_code: string | null
          offer_date: string | null
          offer_role: string | null
          offer_round: number | null
          offer_term_months: number | null
          offer_total_amount: number | null
          offer_type: string | null
          offer_valid_until: string | null
          organization_id: string | null
          selected_for_award_flag: boolean | null
          source_document_id: string | null
          supplier_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          compliant_bid_flag?: boolean | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          fx_rate_to_usd?: number | null
          id?: string
          notes?: string | null
          offer_currency_code?: string | null
          offer_date?: string | null
          offer_role?: string | null
          offer_round?: number | null
          offer_term_months?: number | null
          offer_total_amount?: number | null
          offer_type?: string | null
          offer_valid_until?: string | null
          organization_id?: string | null
          selected_for_award_flag?: boolean | null
          source_document_id?: string | null
          supplier_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          compliant_bid_flag?: boolean | null
          created_at?: string | null
          created_by?: string | null
          event_id?: string | null
          fx_rate_to_usd?: number | null
          id?: string
          notes?: string | null
          offer_currency_code?: string | null
          offer_date?: string | null
          offer_role?: string | null
          offer_round?: number | null
          offer_term_months?: number | null
          offer_total_amount?: number | null
          offer_type?: string | null
          offer_valid_until?: string | null
          organization_id?: string | null
          selected_for_award_flag?: boolean | null
          source_document_id?: string | null
          supplier_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_offers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offers_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "sourcing_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offers_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_offers_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      suppliers: {
        Row: {
          country_code: string | null
          created_at: string | null
          diversity_flag: boolean | null
          id: string
          next_review_date: string | null
          notes: string | null
          organization_id: string | null
          preferred_flag: boolean | null
          relationship_owner_id: string | null
          risk_rating: string | null
          supplier_name: string
          supplier_normalized_name: string
          supplier_status: string | null
          updated_at: string | null
          website: string | null
        }
        Insert: {
          country_code?: string | null
          created_at?: string | null
          diversity_flag?: boolean | null
          id?: string
          next_review_date?: string | null
          notes?: string | null
          organization_id?: string | null
          preferred_flag?: boolean | null
          relationship_owner_id?: string | null
          risk_rating?: string | null
          supplier_name: string
          supplier_normalized_name?: string
          supplier_status?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Update: {
          country_code?: string | null
          created_at?: string | null
          diversity_flag?: boolean | null
          id?: string
          next_review_date?: string | null
          notes?: string | null
          organization_id?: string | null
          preferred_flag?: boolean | null
          relationship_owner_id?: string | null
          risk_rating?: string | null
          supplier_name?: string
          supplier_normalized_name?: string
          supplier_status?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_relationship_owner_id_fkey"
            columns: ["relationship_owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      clone_org_data: {
        Args: { p_owner: string; p_source: string; p_target: string }
        Returns: number
      }
      current_org_id: { Args: never; Returns: string }
      update_workspace_settings:
        | {
            Args: {
              p_currency_code: string
              p_date_format: string
              p_default_recognition_method: string
              p_fiscal_year_start_month: number
              p_full_name: string
              p_hard_reduction_approval_threshold: number
              p_locale: string
              p_organization_name: string
              p_require_baseline: boolean
              p_timezone: string
            }
            Returns: undefined
          }
        | {
            Args: {
              p_currency_code: string
              p_date_format: string
              p_default_recognition_method: string
              p_fiscal_year_start_month: number
              p_full_name: string
              p_hard_reduction_approval_threshold: number
              p_locale: string
              p_organization_name: string
              p_require_baseline: boolean
              p_support_projects_enabled: boolean
              p_timezone: string
            }
            Returns: undefined
          }
      update_workspace_settings_v2: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_descriptions_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v3: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_descriptions_enabled: boolean
          p_project_owners_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v4: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_cost_centers_enabled: boolean
          p_project_descriptions_enabled: boolean
          p_project_owners_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v5: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_categories_enabled: boolean
          p_project_cost_centers_enabled: boolean
          p_project_descriptions_enabled: boolean
          p_project_owners_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v6: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_business_units_enabled: boolean
          p_project_categories_enabled: boolean
          p_project_cost_centers_enabled: boolean
          p_project_descriptions_enabled: boolean
          p_project_owners_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v7: {
        Args: {
          p_currency_code: string
          p_date_format: string
          p_default_recognition_method: string
          p_fiscal_year_start_month: number
          p_full_name: string
          p_hard_reduction_approval_threshold: number
          p_locale: string
          p_organization_name: string
          p_project_business_units_enabled: boolean
          p_project_categories_enabled: boolean
          p_project_cost_centers_enabled: boolean
          p_project_descriptions_enabled: boolean
          p_project_owners_enabled: boolean
          p_project_updates_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
