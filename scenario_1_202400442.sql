DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(150) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED')),
    loan_date      TIMESTAMP DEFAULT now()
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 5),
    ('Computer Networks', 2),
    ('Operating Systems', 0);

SELECT * FROM books ORDER BY book_id;
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '% : LOW on copies (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', counter;
        counter := counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan rejected for student %: requested %, only % available',
            p_student_number, p_quantity, v_available;
    ELSE
        UPDATE books SET available_copies = available_copies - p_quantity
        WHERE book_id = p_book_id;

        INSERT INTO book_loans (book_id, student_number, quantity)
        VALUES (p_book_id, p_student_number, p_quantity);

        RAISE NOTICE 'Loan recorded for student %: % copies of book %',
            p_student_number, p_quantity, p_book_id;
    END IF;
END $$;
CALL borrow_book(1, 'S1001', 2);
CALL borrow_book(2, 'S1002', 1);
CALL borrow_book(2, 'S1003', 5);

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned; no copies restored', p_loan_id;
    ELSE
        UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
        UPDATE books SET available_copies = available_copies + v_qty
        WHERE book_id = v_book_id;
        RAISE NOTICE 'Loan % returned; % copies restored', p_loan_id, v_qty;
    END IF;
END $$;
CALL return_book(1);
CALL return_book(1);

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 2 ORDER BY available_copies;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies remaining: % (% left)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;
DO $$
BEGIN
    CALL borrow_book(1, 'S1004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
