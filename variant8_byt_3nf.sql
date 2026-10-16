/* =====================================================================
   Вариант 8. Обработка заказов в службе быта

   Запуск:  psql -U postgres -d mydb -f variant8_byt_3nf.sql
   ===================================================================== */

DROP SCHEMA IF EXISTS byt CASCADE;
CREATE SCHEMA byt;
SET search_path TO byt;

COMMENT ON SCHEMA byt IS 'Служба быта: приём и обработка заказов (3NF)';

/* ---------------------------------------------------------------------
   2. СПРАВОЧНИКИ
   --------------------------------------------------------------------- */

-- Должности сотрудников
CREATE TABLE position (
    position_id   SERIAL       PRIMARY KEY,
    position_name VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE position IS 'Справочник должностей (приёмщик, мастер, администратор)';

-- Категории услуг
CREATE TABLE service_category (
    category_id   SERIAL       PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE service_category IS 'Категории услуг (ремонт обуви, химчистка, ремонт техники и т.д.)';

-- Статусы заказа
CREATE TABLE order_status (
    status_id   SMALLINT     PRIMARY KEY,
    status_name VARCHAR(50)  NOT NULL UNIQUE,
    is_final    BOOLEAN      NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE  order_status          IS 'Справочник статусов обработки заказа';
COMMENT ON COLUMN order_status.is_final IS 'Признак конечного статуса (выдан / отменён)';

-- Способы оплаты
CREATE TABLE payment_method (
    method_id   SMALLINT    PRIMARY KEY,
    method_name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE payment_method IS 'Справочник способов оплаты';

/* ---------------------------------------------------------------------
   3. ОСНОВНЫЕ СУЩНОСТИ
   --------------------------------------------------------------------- */

-- Пункты приёма заказов
CREATE TABLE branch (
    branch_id   SERIAL        PRIMARY KEY,
    branch_name VARCHAR(100)  NOT NULL,
    address     VARCHAR(255)  NOT NULL,
    phone       VARCHAR(20)
);
COMMENT ON TABLE branch IS 'Пункты приёма заказов службы быта';

-- Клиенты
CREATE TABLE client (
    client_id   SERIAL       PRIMARY KEY,
    last_name   VARCHAR(50)  NOT NULL,
    first_name  VARCHAR(50)  NOT NULL,
    middle_name VARCHAR(50),
    phone       VARCHAR(20)  NOT NULL UNIQUE,
    email       VARCHAR(100),
    address     VARCHAR(255)
);
COMMENT ON TABLE client IS 'Клиенты (заказчики)';

-- Сотрудники
CREATE TABLE employee (
    employee_id SERIAL       PRIMARY KEY,
    last_name   VARCHAR(50)  NOT NULL,
    first_name  VARCHAR(50)  NOT NULL,
    middle_name VARCHAR(50),
    position_id INTEGER      NOT NULL REFERENCES position(position_id),
    branch_id   INTEGER      NOT NULL REFERENCES branch(branch_id),
    hire_date   DATE         NOT NULL DEFAULT CURRENT_DATE,
    phone       VARCHAR(20)
);
COMMENT ON TABLE employee IS 'Сотрудники (приёмщики, мастера)';

-- Услуги (прайс-лист)
CREATE TABLE service (
    service_id    SERIAL         PRIMARY KEY,
    category_id   INTEGER        NOT NULL REFERENCES service_category(category_id),
    service_name  VARCHAR(150)   NOT NULL,
    base_price    NUMERIC(10,2)  NOT NULL CHECK (base_price >= 0),
    duration_days SMALLINT       NOT NULL DEFAULT 1 CHECK (duration_days > 0),
    UNIQUE (category_id, service_name)
);
COMMENT ON TABLE  service               IS 'Перечень услуг и действующие цены';
COMMENT ON COLUMN service.duration_days IS 'Типовой срок исполнения, дней';

/* ---------------------------------------------------------------------
   4. ЗАКАЗЫ И ИХ ОБРАБОТКА
   --------------------------------------------------------------------- */

-- Заказ (заголовок)
CREATE TABLE service_order (
    order_id       SERIAL       PRIMARY KEY,
    client_id      INTEGER      NOT NULL REFERENCES client(client_id),
    branch_id      INTEGER      NOT NULL REFERENCES branch(branch_id),
    accepted_by    INTEGER      NOT NULL REFERENCES employee(employee_id),
    status_id      SMALLINT     NOT NULL REFERENCES order_status(status_id),
    created_at     TIMESTAMP    NOT NULL DEFAULT now(),
    planned_date   DATE         NOT NULL,
    completed_date DATE,
    comment        TEXT,
    CHECK (planned_date >= created_at::date),
    CHECK (completed_date IS NULL OR completed_date >= created_at::date)
);
COMMENT ON TABLE  service_order            IS 'Заказ клиента (заголовок). Сумма не хранится, считается в представлении v_order_total';
COMMENT ON COLUMN service_order.accepted_by IS 'Сотрудник, принявший заказ';
COMMENT ON COLUMN service_order.status_id   IS 'Текущий статус заказа';

-- Позиции заказа
CREATE TABLE order_item (
    order_id    INTEGER        NOT NULL REFERENCES service_order(order_id) ON DELETE CASCADE,
    item_no     SMALLINT       NOT NULL,
    service_id  INTEGER        NOT NULL REFERENCES service(service_id),
    executor_id INTEGER        REFERENCES employee(employee_id),
    quantity    SMALLINT       NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price  NUMERIC(10,2)  NOT NULL CHECK (unit_price >= 0),
    item_note   VARCHAR(255),
    PRIMARY KEY (order_id, item_no)
);
COMMENT ON TABLE  order_item            IS 'Позиции (услуги) заказа';
COMMENT ON COLUMN order_item.unit_price IS 'Цена на момент оформления (фиксируется, т.к. прайс меняется)';
COMMENT ON COLUMN order_item.executor_id IS 'Мастер-исполнитель позиции';

-- История смены статусов (ход обработки заказа)
CREATE TABLE order_status_history (
    history_id  SERIAL     PRIMARY KEY,
    order_id    INTEGER    NOT NULL REFERENCES service_order(order_id) ON DELETE CASCADE,
    status_id   SMALLINT   NOT NULL REFERENCES order_status(status_id),
    changed_at  TIMESTAMP  NOT NULL DEFAULT now(),
    changed_by  INTEGER    NOT NULL REFERENCES employee(employee_id),
    note        VARCHAR(255)
);
COMMENT ON TABLE order_status_history IS 'Журнал обработки заказа: кто и когда перевёл заказ в статус';

-- Оплата
CREATE TABLE payment (
    payment_id  SERIAL         PRIMARY KEY,
    order_id    INTEGER        NOT NULL REFERENCES service_order(order_id),
    method_id   SMALLINT       NOT NULL REFERENCES payment_method(method_id),
    amount      NUMERIC(10,2)  NOT NULL CHECK (amount > 0),
    paid_at     TIMESTAMP      NOT NULL DEFAULT now(),
    received_by INTEGER        NOT NULL REFERENCES employee(employee_id)
);
COMMENT ON TABLE payment IS 'Платежи по заказам (предоплата и оплата при выдаче)';

/* ---------------------------------------------------------------------
   5. ИНДЕКСЫ (по внешним ключам и частым фильтрам)
   --------------------------------------------------------------------- */
CREATE INDEX ix_order_client   ON service_order (client_id);
CREATE INDEX ix_order_status   ON service_order (status_id);
CREATE INDEX ix_order_created  ON service_order (created_at);
CREATE INDEX ix_item_service   ON order_item (service_id);
CREATE INDEX ix_item_executor  ON order_item (executor_id);
CREATE INDEX ix_hist_order     ON order_status_history (order_id);
CREATE INDEX ix_payment_order  ON payment (order_id);
CREATE INDEX ix_employee_branch ON employee (branch_id);

/* ---------------------------------------------------------------------
   6. ПРЕДСТАВЛЕНИЯ
   --------------------------------------------------------------------- */

-- Сумма заказа и оплаты
CREATE VIEW v_order_total AS
SELECT o.order_id,
       COALESCE(i.total, 0)               AS order_sum,
       COALESCE(p.paid, 0)                AS paid_sum,
       COALESCE(i.total, 0) - COALESCE(p.paid, 0) AS debt
FROM service_order o
LEFT JOIN (SELECT order_id, SUM(quantity * unit_price) AS total
           FROM order_item GROUP BY order_id) i ON i.order_id = o.order_id
LEFT JOIN (SELECT order_id, SUM(amount) AS paid
           FROM payment GROUP BY order_id) p ON p.order_id = o.order_id;
COMMENT ON VIEW v_order_total IS 'Сумма заказа, оплачено, остаток долга';

-- Сводка по заказам
CREATE VIEW v_order_info AS
SELECT o.order_id,
       o.created_at,
       c.last_name || ' ' || c.first_name AS client,
       b.branch_name,
       s.status_name,
       t.order_sum, t.paid_sum, t.debt
FROM service_order o
JOIN client       c ON c.client_id = o.client_id
JOIN branch       b ON b.branch_id = o.branch_id
JOIN order_status s ON s.status_id = o.status_id
JOIN v_order_total t ON t.order_id = o.order_id;

/* ---------------------------------------------------------------------
   7. ТЕСТОВЫЕ ДАННЫЕ
   --------------------------------------------------------------------- */
INSERT INTO order_status (status_id, status_name, is_final) VALUES
 (1, 'Принят',            FALSE),
 (2, 'В работе',          FALSE),
 (3, 'Готов к выдаче',    FALSE),
 (4, 'Выдан',             TRUE),
 (5, 'Отменён',           TRUE);

INSERT INTO payment_method (method_id, method_name) VALUES
 (1, 'Наличные'), (2, 'Банковская карта'), (3, 'Безналичный перевод');

INSERT INTO position (position_name) VALUES
 ('Приёмщик'), ('Мастер'), ('Администратор');

INSERT INTO service_category (category_name) VALUES
 ('Ремонт обуви'), ('Химчистка'), ('Ремонт одежды'), ('Ремонт бытовой техники');

INSERT INTO branch (branch_name, address, phone) VALUES
 ('Пункт №1', 'г. Рига, ул. Бривибас, 10', '+371 20000001'),
 ('Пункт №2', 'г. Рига, ул. Матиса, 25',   '+371 20000002');

INSERT INTO employee (last_name, first_name, middle_name, position_id, branch_id, hire_date, phone) VALUES
 ('Иванова', 'Анна',   'Петровна',   1, 1, '2022-03-01', '+371 21000001'),
 ('Сидоров', 'Олег',   'Иванович',   2, 1, '2021-06-15', '+371 21000002'),
 ('Берзиньш','Янис',   NULL,         2, 2, '2020-09-10', '+371 21000003'),
 ('Орлова',  'Мария',  'Сергеевна',  1, 2, '2023-01-20', '+371 21000004');

INSERT INTO service (category_id, service_name, base_price, duration_days) VALUES
 (1, 'Замена набоек',            8.00, 1),
 (1, 'Замена молнии',           12.00, 2),
 (2, 'Химчистка пальто',        20.00, 3),
 (2, 'Химчистка куртки',        15.00, 3),
 (3, 'Подгонка брюк по длине',   7.00, 1),
 (4, 'Ремонт утюга',            18.00, 5);

INSERT INTO client (last_name, first_name, middle_name, phone, email, address) VALUES
 ('Петров',  'Павел',   'Андреевич', '+371 26000001', 'petrov@example.com',  'г. Рига, ул. Лачплеша, 5'),
 ('Кузнецова','Елена',  NULL,        '+371 26000002', 'kuznetsova@example.com', 'г. Рига, ул. Дзирнаву, 12'),
 ('Лиепа',   'Андрис',  NULL,        '+371 26000003', NULL, NULL);

-- Заказ 1: выдан и оплачен
INSERT INTO service_order (client_id, branch_id, accepted_by, status_id, created_at, planned_date, completed_date, comment)
VALUES (1, 1, 1, 4, '2026-10-01 10:00', '2026-10-04', '2026-10-03', 'Срочно не требуется');
INSERT INTO order_item (order_id, item_no, service_id, executor_id, quantity, unit_price) VALUES
 (1, 1, 3, 2, 1, 20.00),
 (1, 2, 5, 2, 1,  7.00);
INSERT INTO order_status_history (order_id, status_id, changed_at, changed_by) VALUES
 (1, 1, '2026-10-01 10:00', 1),
 (1, 2, '2026-10-01 14:00', 2),
 (1, 3, '2026-10-03 12:00', 2),
 (1, 4, '2026-10-03 17:30', 1);
INSERT INTO payment (order_id, method_id, amount, paid_at, received_by) VALUES
 (1, 2, 27.00, '2026-10-03 17:30', 1);

-- Заказ 2: в работе, предоплата
INSERT INTO service_order (client_id, branch_id, accepted_by, status_id, created_at, planned_date)
VALUES (2, 2, 4, 2, '2026-10-14 11:20', '2026-10-19');
INSERT INTO order_item (order_id, item_no, service_id, executor_id, quantity, unit_price) VALUES
 (2, 1, 6, 3, 1, 18.00);
INSERT INTO order_status_history (order_id, status_id, changed_at, changed_by) VALUES
 (2, 1, '2026-10-14 11:20', 4),
 (2, 2, '2026-10-15 09:00', 3);
INSERT INTO payment (order_id, method_id, amount, paid_at, received_by) VALUES
 (2, 1, 5.00, '2026-10-14 11:25', 4);

-- Заказ 3: только принят
INSERT INTO service_order (client_id, branch_id, accepted_by, status_id, created_at, planned_date)
VALUES (3, 1, 1, 1, '2026-10-16 09:30', '2026-10-17');
INSERT INTO order_item (order_id, item_no, service_id, quantity, unit_price) VALUES
 (3, 1, 1, 1, 8.00);
INSERT INTO order_status_history (order_id, status_id, changed_at, changed_by) VALUES
 (3, 1, '2026-10-16 09:30', 1);

-- Контроль
-- SELECT * FROM byt.v_order_info ORDER BY order_id;
