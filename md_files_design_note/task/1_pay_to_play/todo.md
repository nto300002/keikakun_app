stripe test_helpers test_clocks create \
    --frozen-time=$(date -u +%s) \
    --name="cancel_test_$(date +%s)"


stripe subscriptions update sub_1ShJi5BxyBErCNcAnS6FJOnW \
    -d cancel_at_period_end=true


    stripe test_helpers test_clocks advance clock_1ShK2mBxyBErCNcAIzGFQtil \
    --frozen-time=$(($(date -u +%s) + (180 * 86400))) 