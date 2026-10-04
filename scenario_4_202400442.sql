DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;

CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED', 'REVERSED')),
    dispensed_at   TIMESTAMP DEFAULT now()
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 8),
    ('Cetirizine 10mg', 0);

SELECT * FROM medicines ORDER BY medicine_id;
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 10 THEN
            RAISE NOTICE '% : LOW ON STOCK (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Stock review day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', n;
    END LOOP;
END $$;
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE NOTICE 'Dispensing rejected for student %: requested %, only % in stock',
            p_student_number, p_quantity, v_stock;
    ELSE
        UPDATE medicines SET stock_quantity = stock_quantity - p_quantity
        WHERE medicine_id = p_medicine_id;

        INSERT INTO dispensing_records (medicine_id, student_number, quantity)
        VALUES (p_medicine_id, p_student_number, p_quantity);

        RAISE NOTICE 'Dispensed % units of medicine % to student %',
            p_quantity, p_medicine_id, p_student_number;
    END IF;
END $$;
CALL dispense_medicine(1, 'S3001', 20);
CALL dispense_medicine(2, 'S3002', 5);
CALL dispense_medicine(2, 'S3003', 10);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(10);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed; stock not restored again', p_record_id;
    ELSE
        UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
        UPDATE medicines SET stock_quantity = stock_quantity + v_qty
        WHERE medicine_id = v_medicine_id;
        RAISE NOTICE 'Record % reversed; % units restored', p_record_id, v_qty;
    END IF;
END $$;
CALL reverse_dispensing(1);
CALL reverse_dispensing(1);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
DO $$
DECLARE
    v_threshold INT := 10;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_limit ORDER BY stock_quantity;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % has % units', v_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;
DO $$
BEGIN
    CALL dispense_medicine(1, 'S3004', -5);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;