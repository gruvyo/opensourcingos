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
          created_by: string | null
          event_id: string | null
          id: string
          line_number: number
          organization_id: string | null
          scope_line_id: string | null
          updated_at: string | null
          updated_by: string | null
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
          created_by?: string | null
          event_id?: string | null
          id?: string
          line_number: number
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
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
          created_by?: string | null
          event_id?: string | null
          id?: string
          line_number?: number
          organization_id?: string | null
          scope_line_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
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
            foreignKeyName: "award_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          {
            foreignKeyName: "award_lines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          created_by: string | null
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
          updated_by: string | null
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
          created_by?: string | null
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
          updated_by?: string | null
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
          created_by?: string | null
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
          updated_by?: string | null
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
            foreignKeyName: "baseline_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          {
            foreignKeyName: "baseline_lines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          created_by: string | null
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
          updated_by: string | null
        }
        Insert: {
          baseline_quantity?: number | null
          business_equivalency_confirmed?: boolean | null
          business_equivalency_confirmed_by?: string | null
          category_id?: string | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
        }
        Update: {
          baseline_quantity?: number | null
          business_equivalency_confirmed?: boolean | null
          business_equivalency_confirmed_by?: string | null
          category_id?: string | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
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
            foreignKeyName: "event_scope_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          {
            foreignKeyName: "event_scope_lines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          project_incumbent_suppliers_enabled: boolean
          project_owners_enabled: boolean
          project_updates_enabled: boolean
          require_baseline_for_hard_reduction: boolean
          savings_realization_enabled: boolean
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
          project_incumbent_suppliers_enabled?: boolean
          project_owners_enabled?: boolean
          project_updates_enabled?: boolean
          require_baseline_for_hard_reduction?: boolean
          savings_realization_enabled?: boolean
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
          project_incumbent_suppliers_enabled?: boolean
          project_owners_enabled?: boolean
          project_updates_enabled?: boolean
          require_baseline_for_hard_reduction?: boolean
          savings_realization_enabled?: boolean
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
          is_terminal: boolean
          label: string
          organization_id: string
          project_type: string | null
          requires_savings_disposition: boolean
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
          is_terminal?: boolean
          label: string
          organization_id: string
          project_type?: string | null
          requires_savings_disposition?: boolean
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
          is_terminal?: boolean
          label?: string
          organization_id?: string
          project_type?: string | null
          requires_savings_disposition?: boolean
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
          comparison_rebased_at: string | null
          comparison_rebased_by: string | null
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
          projected_avoidance_amount: number | null
          projected_reduction_amount: number | null
          projected_savings: number | null
          realization_status: string | null
          realized_avoidance_amount: number | null
          realized_reduction_amount: number | null
          realized_savings: number | null
          savings_calculation_id: string | null
          savings_period_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          actual_amount?: number | null
          baseline_amount?: number | null
          comparison_rebased_at?: string | null
          comparison_rebased_by?: string | null
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
          projected_avoidance_amount?: number | null
          projected_reduction_amount?: number | null
          projected_savings?: number | null
          realization_status?: string | null
          realized_avoidance_amount?: number | null
          realized_reduction_amount?: number | null
          realized_savings?: number | null
          savings_calculation_id?: string | null
          savings_period_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          actual_amount?: number | null
          baseline_amount?: number | null
          comparison_rebased_at?: string | null
          comparison_rebased_by?: string | null
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
          projected_avoidance_amount?: number | null
          projected_reduction_amount?: number | null
          projected_savings?: number | null
          realization_status?: string | null
          realized_avoidance_amount?: number | null
          realized_reduction_amount?: number | null
          realized_savings?: number | null
          savings_calculation_id?: string | null
          savings_period_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "realization_periods_comparison_rebased_by_fkey"
            columns: ["comparison_rebased_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
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
            foreignKeyName: "realization_periods_savings_period_id_fkey"
            columns: ["savings_period_id"]
            isOneToOne: false
            referencedRelation: "savings_periods"
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
          created_by: string | null
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
          updated_by: string | null
        }
        Insert: {
          awarded_extended_amount?: number | null
          awarded_quantity?: number | null
          awarded_unit_price?: number | null
          baseline_extended_amount?: number | null
          baseline_quantity?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
        }
        Update: {
          awarded_extended_amount?: number | null
          awarded_quantity?: number | null
          awarded_unit_price?: number | null
          baseline_extended_amount?: number | null
          baseline_quantity?: number | null
          baseline_unit_price?: number | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "savings_calculation_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
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
          {
            foreignKeyName: "savings_calculation_lines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          executed_at: string | null
          executed_by: string | null
          execution_note: string | null
          gross_savings_amount: number | null
          id: string
          legacy_execution_actor_missing: boolean
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
          executed_at?: string | null
          executed_by?: string | null
          execution_note?: string | null
          gross_savings_amount?: number | null
          id?: string
          legacy_execution_actor_missing?: boolean
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
          executed_at?: string | null
          executed_by?: string | null
          execution_note?: string | null
          gross_savings_amount?: number | null
          id?: string
          legacy_execution_actor_missing?: boolean
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
            foreignKeyName: "savings_calculations_executed_by_fkey"
            columns: ["executed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
          executed_baseline_amount: number | null
          executed_cost_avoidance_amount: number | null
          executed_cost_reduction_amount: number | null
          executed_final_amount: number | null
          executed_opening_amount: number | null
          executed_total_savings_amount: number | null
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
          executed_baseline_amount?: number | null
          executed_cost_avoidance_amount?: number | null
          executed_cost_reduction_amount?: number | null
          executed_final_amount?: number | null
          executed_opening_amount?: number | null
          executed_total_savings_amount?: number | null
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
          executed_baseline_amount?: number | null
          executed_cost_avoidance_amount?: number | null
          executed_cost_reduction_amount?: number | null
          executed_final_amount?: number | null
          executed_opening_amount?: number | null
          executed_total_savings_amount?: number | null
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
          project_type: string
          recognition_end_date: string | null
          recognition_start_date: string | null
          savings_disposition: string | null
          savings_disposition_at: string | null
          savings_disposition_by: string | null
          savings_disposition_reason: string | null
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
          project_type?: string
          recognition_end_date?: string | null
          recognition_start_date?: string | null
          savings_disposition?: string | null
          savings_disposition_at?: string | null
          savings_disposition_by?: string | null
          savings_disposition_reason?: string | null
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
          project_type?: string
          recognition_end_date?: string | null
          recognition_start_date?: string | null
          savings_disposition?: string | null
          savings_disposition_at?: string | null
          savings_disposition_by?: string | null
          savings_disposition_reason?: string | null
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
            foreignKeyName: "sourcing_events_savings_disposition_by_fkey"
            columns: ["savings_disposition_by"]
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
      supplier_certifications: {
        Row: {
          certificate_number: string | null
          certification_name: string
          created_at: string
          created_by: string | null
          evidence_url: string | null
          expires_on: string | null
          id: string
          issued_on: string | null
          issuer: string | null
          organization_id: string
          supplier_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          certificate_number?: string | null
          certification_name: string
          created_at?: string
          created_by?: string | null
          evidence_url?: string | null
          expires_on?: string | null
          id?: string
          issued_on?: string | null
          issuer?: string | null
          organization_id: string
          supplier_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          certificate_number?: string | null
          certification_name?: string
          created_at?: string
          created_by?: string | null
          evidence_url?: string | null
          expires_on?: string | null
          id?: string
          issued_on?: string | null
          issuer?: string | null
          organization_id?: string
          supplier_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_certifications_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_certifications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_certifications_supplier_workspace_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "supplier_certifications_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_contacts: {
        Row: {
          contact_name: string
          created_at: string
          created_by: string | null
          email: string | null
          id: string
          is_primary: boolean
          job_title: string | null
          organization_id: string
          phone: string | null
          supplier_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          contact_name: string
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          is_primary?: boolean
          job_title?: string | null
          organization_id: string
          phone?: string | null
          supplier_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          contact_name?: string
          created_at?: string
          created_by?: string | null
          email?: string | null
          id?: string
          is_primary?: boolean
          job_title?: string | null
          organization_id?: string
          phone?: string | null
          supplier_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_contacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_contacts_supplier_workspace_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "supplier_contacts_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_notes: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          id: string
          occurred_on: string
          organization_id: string
          supplier_id: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          id?: string
          occurred_on?: string
          organization_id: string
          supplier_id: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          id?: string
          occurred_on?: string
          organization_id?: string
          supplier_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "supplier_notes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_notes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_notes_supplier_workspace_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      supplier_offer_lines: {
        Row: {
          annualized_offer_amount: number | null
          compliance_status: string | null
          created_at: string | null
          created_by: string | null
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
          updated_by: string | null
        }
        Insert: {
          annualized_offer_amount?: number | null
          compliance_status?: string | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
        }
        Update: {
          annualized_offer_amount?: number | null
          compliance_status?: string | null
          created_at?: string | null
          created_by?: string | null
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
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_offer_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
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
          {
            foreignKeyName: "supplier_offer_lines_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
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
      supplier_performance_reviews: {
        Row: {
          commercial_score: number | null
          compliance_score: number | null
          created_at: string
          created_by: string | null
          delivery_score: number | null
          id: string
          next_review_date: string | null
          organization_id: string
          overall_score: number
          quality_score: number | null
          review_date: string
          review_title: string
          summary: string
          supplier_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          commercial_score?: number | null
          compliance_score?: number | null
          created_at?: string
          created_by?: string | null
          delivery_score?: number | null
          id?: string
          next_review_date?: string | null
          organization_id: string
          overall_score: number
          quality_score?: number | null
          review_date: string
          review_title: string
          summary: string
          supplier_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          commercial_score?: number | null
          compliance_score?: number | null
          created_at?: string
          created_by?: string | null
          delivery_score?: number | null
          id?: string
          next_review_date?: string | null
          organization_id?: string
          overall_score?: number
          quality_score?: number | null
          review_date?: string
          review_title?: string
          summary?: string
          supplier_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_performance_reviews_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_performance_reviews_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_performance_reviews_supplier_workspace_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "supplier_performance_reviews_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_risks: {
        Row: {
          created_at: string
          created_by: string | null
          description: string
          evidence_url: string | null
          id: string
          identified_on: string
          organization_id: string
          risk_status: string
          risk_title: string
          severity: string
          supplier_id: string
          target_resolution_date: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description: string
          evidence_url?: string | null
          id?: string
          identified_on: string
          organization_id: string
          risk_status?: string
          risk_title: string
          severity: string
          supplier_id: string
          target_resolution_date?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string
          evidence_url?: string | null
          id?: string
          identified_on?: string
          organization_id?: string
          risk_status?: string
          risk_title?: string
          severity?: string
          supplier_id?: string
          target_resolution_date?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_risks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_risks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_risks_supplier_workspace_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "supplier_risks_updated_by_fkey"
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
      add_baseline_line: {
        Args: { p_baseline_id: string; p_line: Json }
        Returns: string
      }
      assert_jsonb_money_cent_exact: {
        Args: { p_fields: string[]; p_items: Json }
        Returns: undefined
      }
      clone_org_data: {
        Args: { p_owner: string; p_source: string; p_target: string }
        Returns: number
      }
      complete_sourcing_project: {
        Args: { p_disposition: string; p_event_id: string; p_reason?: string }
        Returns: undefined
      }
      confirm_business_equivalency: {
        Args: { p_confirmed: boolean; p_scope_line_id: string }
        Returns: undefined
      }
      correct_savings_execution: {
        Args: {
          p_calc_id: string
          p_calculation: Json
          p_note: string
          p_periods: Json
        }
        Returns: undefined
      }
      correct_savings_execution_unchecked: {
        Args: {
          p_calc_id: string
          p_calculation: Json
          p_note: string
          p_periods: Json
        }
        Returns: undefined
      }
      current_org_id: { Args: never; Returns: string }
      delete_baseline_line: {
        Args: { p_baseline_line_id: string }
        Returns: undefined
      }
      derive_realization_status: {
        Args: {
          p_projected_avoidance: number
          p_projected_reduction: number
          p_realized_avoidance: number
          p_realized_reduction: number
        }
        Returns: string
      }
      mark_savings_schedule_executed: {
        Args: { p_execution_note?: string; p_savings_calculation_id: string }
        Returns: undefined
      }
      replace_savings_schedule: {
        Args: {
          p_periods: Json
          p_savings_calculation_id: string
          p_schedule_period_type: string
          p_schedule_start_month: number
          p_schedule_start_year: number
        }
        Returns: undefined
      }
      replace_savings_schedule_unchecked: {
        Args: {
          p_periods: Json
          p_savings_calculation_id: string
          p_schedule_period_type: string
          p_schedule_start_month: number
          p_schedule_start_year: number
        }
        Returns: undefined
      }
      reverse_savings_execution: {
        Args: {
          p_calc_id: string
          p_disposition_action: string
          p_note: string
        }
        Returns: undefined
      }
      save_estimated_savings_calculation: {
        Args: {
          p_calculation: Json
          p_calculation_id?: string
          p_event_id: string
        }
        Returns: string
      }
      select_baseline: { Args: { p_baseline_id: string }; Returns: undefined }
      set_finance_validation: {
        Args: { p_realization_period_id: string; p_validated: boolean }
        Returns: undefined
      }
      set_hard_reduction_override: {
        Args: { p_baseline_id: string; p_enabled: boolean; p_reason?: string }
        Returns: undefined
      }
      set_offer_role: {
        Args: { p_offer_id: string; p_role?: string }
        Returns: undefined
      }
      sync_realization_periods: {
        Args: { p_event_id: string }
        Returns: number
      }
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
      update_workspace_settings_v8: {
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
          p_project_incumbent_suppliers_enabled: boolean
          p_project_owners_enabled: boolean
          p_project_updates_enabled: boolean
          p_require_baseline: boolean
          p_support_projects_enabled: boolean
          p_timezone: string
        }
        Returns: undefined
      }
      update_workspace_settings_v9: {
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
          p_project_incumbent_suppliers_enabled: boolean
          p_project_owners_enabled: boolean
          p_project_updates_enabled: boolean
          p_require_baseline: boolean
          p_savings_realization_enabled: boolean
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
