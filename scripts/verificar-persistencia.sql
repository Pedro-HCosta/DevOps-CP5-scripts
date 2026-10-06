-- Execute após CADA operação no vídeo (substitua os IDs).
SELECT id, nome, email FROM clientes ORDER BY id;
SELECT id, numero, tipo, saldo, cliente_id FROM contas ORDER BY id;
SELECT c.nome, ct.numero, ct.tipo, ct.saldo FROM clientes c JOIN contas ct ON ct.cliente_id=c.id;
