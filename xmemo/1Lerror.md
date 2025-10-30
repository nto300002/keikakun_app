

---------------

# Localでの問題 (最優先)
- ログインページにいる時に下記エラーが発生

GET http://localhost:8000/api/v1/staffs/me 401 (Unauthorized)

[DEBUG HTTP] Response not OK. Status: 401

[DEBUG HTTP] 401 Unauthorized - triggering logout

POST http://localhost:8000/api/v1/auth/logout 401 (Unauthorized)

ログイン、ログアウトは問題なくできる