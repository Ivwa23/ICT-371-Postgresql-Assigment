DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;

CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id        SERIAL PRIMARY KEY,
    session_id            INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer              VARCHAR(100) NOT NULL,
    workstations_reserved INT NOT NULL CHECK (workstations_reserved > 0),
    status                VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                          CHECK (status IN ('RESERVED', 'CANCELLED')),
    reserved_at           TIMESTAMP DEFAULT now()
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 Practical', 30),
    ('Tuesday 10:00 Practical', 4),
    ('Wednesday 14:00 Practical', 0);

SELECT * FROM lab_sessions ORDER BY session_id;
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : ENOUGH workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', n;
    END LOOP;
END $$;
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT, p_lecturer VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Reservation rejected for %: requested %, only % available',
            p_lecturer, p_quantity, v_available;
    ELSE
        UPDATE lab_sessions
        SET available_workstations = available_workstations - p_quantity
        WHERE session_id = p_session_id;

        INSERT INTO reservations (session_id, lecturer, workstations_reserved)
        VALUES (p_session_id, p_lecturer, p_quantity);

        RAISE NOTICE 'Reservation recorded for %: % workstations in session %',
            p_lecturer, p_quantity, p_session_id;
    END IF;
END $$;
CALL reserve_workstations(1, 'Dr. Banda', 10);
CALL reserve_workstations(2, 'Mr. Phiri', 2);
CALL reserve_workstations(2, 'Ms. Zulu', 5);

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(10);
BEGIN
    SELECT session_id, workstations_reserved, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled; no workstations released', p_reservation_id;
    ELSE
        UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
        UPDATE lab_sessions
        SET available_workstations = available_workstations + v_qty
        WHERE session_id = v_session_id;
        RAISE NOTICE 'Reservation % cancelled; % workstations released', p_reservation_id, v_qty;
    END IF;
END $$;
CALL cancel_reservation(1);
CALL cancel_reservation(1);

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name lab_sessions.session_name%TYPE;
    v_free lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_free;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations remaining: % (% left)', v_name, v_free;
    END LOOP;
    CLOSE cur_low;
END $$;
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;