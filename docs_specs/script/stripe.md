 docker-compose exec \
   -e RUN_S3_INTEGRATION_TESTS=true \
   -e PYTHONPATH=/app \
   -e SECRET_KEY="test_secret_key_for_pytest" \
   backend python tests/scripts/setup_edge_case_states.py --case 0

 docker-compose exec \
   -e RUN_S3_INTEGRATION_TESTS=true \
   -e PYTHONPATH=/app \
   -e SECRET_KEY="test_secret_key_for_pytest" \
   backend python tests/scripts/cleanup_duplicate_subscriptions.py --delete-all