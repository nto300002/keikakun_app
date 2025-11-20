下記 +α 通知機能
## owner ページ
- 下記全て admin -> ownerというパスになるように変更
http://localhost:3000/admin
k_front/app/(protected)/admin
k_front/components/protected/admin
k_front/components/auth/admin # auth/owner
k_front/app/auth/admin


## バック
- app_admin
```py
class AppAdmin(Base):
    """スタッフ"""
    __tablename__ = 'app_admins'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)

    name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    is_email_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # MFA関連フィールド
    is_mfa_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    mfa_secret: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)  # 暗号化されたTOTPシークレット
    mfa_backup_codes_used: Mapped[int] = mapped_column(Integer, default=0, nullable=False)  # 使用済みバックアップコード数

    # パスワード変更関連
    password_changed_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    failed_password_attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_locked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    locked_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    

    mfa_backup_codes: Mapped[List["MFABackupCode"]] = relationship(back_populates="AppAdmin", cascade="all, delete-orphan")
    mfa_audit_logs: Mapped[List["MFAAuditLog"]] = relationship(back_populates="AppAdmin", cascade="all, delete-orphan")
    
    # MFA関連メソッド
    def set_mfa_secret(self, secret: str) -> None:
        """MFAシークレットを暗号化して設定"""
        from app.core.security import encrypt_mfa_secret
        self.mfa_secret = encrypt_mfa_secret(secret)
    
    def get_mfa_secret(self) -> Optional[str]:
        """MFAシークレットを復号して取得"""
        if not self.mfa_secret:
            return None
        from app.core.security import decrypt_mfa_secret
        return decrypt_mfa_secret(self.mfa_secret)
    
    async def enable_mfa(self, db: AsyncSession, secret: str, recovery_codes: List[str]) -> None:
        """MFAを有効化"""
        self.set_mfa_secret(secret)
        self.is_mfa_enabled = True
        
        # リカバリーコードを保存
        from app.models.mfa import MFABackupCode
        from app.core.security import hash_recovery_code
        
        for code in recovery_codes:
            backup_code = MFABackupCode(
                AppAdmin_id=self.id,
                code_hash=hash_recovery_code(code),
                is_used=False
            )
            db.add(backup_code)
    
    async def disable_mfa(self, db: AsyncSession) -> None:
        """MFAを無効化"""
        self.is_mfa_enabled = False
        self.mfa_secret = None
        self.mfa_backup_codes_used = 0

        # バックアップコードを削除（明示的なDELETEクエリ）
        from app.models.mfa import MFABackupCode
        stmt = delete(MFABackupCode).where(MFABackupCode.AppAdmin_id == self.id)
        await db.execute(stmt)
    
    async def get_backup_codes(self, db: AsyncSession) -> List["MFABackupCode"]:
        """全てのバックアップコードを取得"""
        from app.models.mfa import MFABackupCode
        stmt = select(MFABackupCode).where(MFABackupCode.AppAdmin_id == self.id)
        result = await db.execute(stmt)
        return list(result.scalars().all())
    
    async def get_unused_backup_codes(self, db: AsyncSession) -> List["MFABackupCode"]:
        """未使用のバックアップコードを取得"""
        from app.models.mfa import MFABackupCode
        stmt = select(MFABackupCode).where(
            MFABackupCode.AppAdmin_id == self.id,
            MFABackupCode.is_used == False
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())
    
    async def has_backup_codes_remaining(self, db: AsyncSession) -> bool:
        """未使用のバックアップコードが残っているかチェック"""
        unused_codes = await self.get_unused_backup_codes(db)
        return len(unused_codes) > 0
```


### フロント
- スタッフタブ: 事務所に所属するスタッフ一覧
削除ボタン(スタッフ削除)
権限変更(リクエストなし)
- 事務所タブ: 
事務所グループ新規作成(仮) 仮機能と明記
事務所退会処理: 完全な削除まで30日の猶予 
削除フロー - app_adminに対し、削除通知
- 事務所名変更: ownerのみ権限