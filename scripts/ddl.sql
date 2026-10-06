-- Azure SQL Database. Reaplicável: não apaga registros nem altera tabelas existentes.
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID(N'dbo.clientes', N'U') IS NULL
 BEGIN
 CREATE TABLE clientes (
 id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_clientes PRIMARY KEY,
 nome VARCHAR(120) NOT NULL,
 email VARCHAR(160) NOT NULL,
 CONSTRAINT uk_clientes_email UNIQUE(email)
);
 END;
 IF OBJECT_ID(N'dbo.contas', N'U') IS NULL
 BEGIN
 CREATE TABLE contas (
 id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_contas PRIMARY KEY,
 numero VARCHAR(20) NOT NULL,
 tipo VARCHAR(10) NOT NULL,
 saldo DECIMAL(15,2) NOT NULL,
 cliente_id BIGINT NOT NULL,
 CONSTRAINT uk_contas_numero UNIQUE(numero),
 CONSTRAINT fk_contas_cliente FOREIGN KEY(cliente_id) REFERENCES clientes(id),
 CONSTRAINT ck_contas_saldo CHECK(saldo >= 0),
 CONSTRAINT ck_contas_tipo CHECK(tipo IN ('CORRENTE','POUPANCA'))
);
 END;
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.contas') AND name=N'ix_contas_cliente')
 BEGIN
 CREATE INDEX ix_contas_cliente ON contas(cliente_id);
 END;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
