stripe subscriptions update sub_1ShJJoBxyBErCNcA9CGI3naK \
    -d cancel_at_period_end=true
{
  "id": "sub_1ShJJoBxyBErCNcA9CGI3naK",
  "object": "subscription",
  "application": null,
  "application_fee_percent": null,
  "automatic_tax": {
    "disabled_reason": null,
    "enabled": true,
    "liability": {
      "type": "self"
    }
  },
  "billing_cycle_anchor": 1781827200,
  "billing_cycle_anchor_config": null,
  "billing_mode": {
    "flexible": {
      "proration_discounts": "included"
    },
    "type": "flexible",
    "updated_at": 1766449150
  },
  "billing_thresholds": null,
  "cancel_at": 1781827200,
  "cancel_at_period_end": true,
  "canceled_at": 1766449239,
  "cancellation_details": {
    "comment": null,
    "feedback": "switched_service",
    "reason": "cancellation_requested"
  },
  "collection_method": "charge_automatically",
  "created": 1766449155,
  "currency": "jpy",
  "customer": "cus_TecYgxboEmne6z",
  "customer_account": null,
  "days_until_due": null,
  "default_payment_method": "pm_1ShJJmBxyBErCNcAUNJdsp3g",
  "default_source": null,
  "default_tax_rates": [],
  "description": null,
  "discounts": [],
  "ended_at": null,
  "invoice_settings": {
    "account_tax_ids": null,
    "issuer": {
      "type": "self"
    }
  },
  "items": {
    "object": "list",
    "data": [
      {
        "id": "si_TecYRWXgmUoWim",
        "object": "subscription_item",
        "billing_thresholds": null,
        "created": 1766449155,
        "current_period_end": 1781827200,
        "current_period_start": 1766449155,
        "discounts": [],
        "metadata": {},
        "plan": {
          "id": "price_1SczlUBxyBErCNcAIQxt2zGg",
          "object": "plan",
          "active": true,
          "amount": 6000,
          "amount_decimal": "6000",
          "billing_scheme": "per_unit",
          "created": 1765420680,
          "currency": "jpy",
          "interval": "month",
          "interval_count": 1,
          "livemode": false,
          "metadata": {},
          "meter": null,
          "nickname": null,
          "product": "prod_TaA5aAh04fiyQQ",
          "tiers_mode": null,
          "transform_usage": null,
          "trial_period_days": null,
          "usage_type": "licensed"
        },
        "price": {
          "id": "price_1SczlUBxyBErCNcAIQxt2zGg",
          "object": "price",
          "active": true,
          "billing_scheme": "per_unit",
          "created": 1765420680,
          "currency": "jpy",
          "custom_unit_amount": null,
          "livemode": false,
          "lookup_key": null,
          "metadata": {},
          "nickname": null,
          "product": "prod_TaA5aAh04fiyQQ",
          "recurring": {
            "interval": "month",
            "interval_count": 1,
            "meter": null,
            "trial_period_days": null,
            "usage_type": "licensed"
          },
          "tax_behavior": "unspecified",
          "tiers_mode": null,
          "transform_quantity": null,
          "type": "recurring",
          "unit_amount": 6000,
          "unit_amount_decimal": "6000"
        },
        "quantity": 1,
        "subscription": "sub_1ShJJoBxyBErCNcA9CGI3naK",
        "tax_rates": []
      }
    ],
    "has_more": false,
    "total_count": 1,
    "url": "/v1/subscription_items?subscription=sub_1ShJJoBxyBErCNcA9CGI3naK"
  },
  "latest_invoice": "in_1ShJJnBxyBErCNcAwc1BKhKs",
  "livemode": false,
  "metadata": {
    "created_by_user_id": "cc67e78e-72ea-4f13-abc4-33218c1ff60e",
    "office_id": "0949d359-5e1a-42f3-87da-07b40946efc0",
    "office_name": "事務所TEST"
  },
  "next_pending_invoice_item_invoice": null,
  "on_behalf_of": null,
  "pause_collection": null,
  "payment_settings": {
    "payment_method_options": {
      "acss_debit": null,
      "bancontact": null,
      "card": {
        "network": null,
        "request_three_d_secure": "automatic"
      },
      "customer_balance": null,
      "konbini": null,
      "payto": null,
      "sepa_debit": null,
      "us_bank_account": null
    },
    "payment_method_types": ["card"],
    "save_default_payment_method": "off"
  },
  "pending_invoice_item_interval": null,
  "pending_setup_intent": null,
  "pending_update": null,
  "plan": {
    "id": "price_1SczlUBxyBErCNcAIQxt2zGg",
    "object": "plan",
    "active": true,
    "amount": 6000,
    "amount_decimal": "6000",
    "billing_scheme": "per_unit",
    "created": 1765420680,
    "currency": "jpy",
    "interval": "month",
    "interval_count": 1,
    "livemode": false,
    "metadata": {},
    "meter": null,
    "nickname": null,
    "product": "prod_TaA5aAh04fiyQQ",
    "tiers_mode": null,
    "transform_usage": null,
    "trial_period_days": null,
    "usage_type": "licensed"
  },
  "quantity": 1,
  "schedule": null,
  "start_date": 1766449155,
  "status": "trialing",
  "test_clock": null,
  "transfer_data": null,
  "trial_end": 1781827200,
  "trial_settings": {
    "end_behavior": {
      "missing_payment_method": "create_invoice"
    }
  },
  "trial_start": 1766449155
}




2025-12-23 09:19:35  <--  [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1ShJK5BxyBErCNcAkasKMUUQ]
2025-12-23 09:19:41   --> customer.subscription.updated [evt_1ShJKDBxyBErCNcAwXn9G0tN]
2025-12-23 09:19:43  <--  [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1ShJKDBxyBErCNcAwXn9G0tN]
2025-12-23 09:19:47   --> customer.subscription.updated [evt_1ShJKJBxyBErCNcAUVI3GLtV]
2025-12-23 09:19:50  <--  [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1ShJKJBxyBErCNcAUVI3GLtV]
2025-12-23 09:20:40   --> customer.subscription.updated [evt_1ShJLABxyBErCNcAP6NzFT3S]
2025-12-23 09:20:42  <--  [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1ShJLABxyBErCNcAP6NzFT3S]



2025-12-23 00:19:49,452 - app.services.billing_service - INFO - [Webhook:evt_1ShJKJBxyBErCNcAUVI3GLtV] Scheduled cancellation set for 2026-06-19 00:00:00+00:00
2025-12-23 00:19:49,681 - app.services.billing_service - INFO - [Webhook:evt_1ShJKJBxyBErCNcAUVI3GLtV] Subscription set to canceling - cancel_at_period_end=False, cancel_at=1781827200
2025-12-23 00:20:40,739 - app.services.billing_service - INFO - [Webhook:evt_1ShJLABxyBErCNcAP6NzFT3S] Subscription updated - customer_id=cus_TecYgxboEmne6z, cancel_at_period_end=True, cancel_at=1781827200, status=trialing
2025-12-23 00:20:41,225 - app.services.billing_service - INFO - [Webhook:evt_1ShJLABxyBErCNcAP6NzFT3S] Current billing_status=BillingStatus.canceling
2025-12-23 00:20:41,225 - app.services.billing_service - INFO - [Webhook:evt_1ShJLABxyBErCNcAP6NzFT3S] Scheduled cancellation set for 2026-06-19 00:00:00+00:00
2025-12-23 00:20:41,459 - app.services.billing_service - INFO - [Webhook:evt_1ShJLABxyBErCNcAP6NzFT3S] Subscription set to canceling - cancel_at_period_end=True, cancel_at=1781827200