-- =========================================================
-- II. PROCEDURE
-- =========================================================
-- kiểm tra xem khi một khách hàng muốn gửi 1 lần nhiều thú cưng vào 1 phòng
CREATE OR REPLACE PROCEDURE room_for_multiple_pets (
    p_booking_room_id IN VARCHAR2,
    p_pet_count       IN NUMBER,
    p_max_pet_weight  IN NUMBER
)
AS
    v_max_pets       type_room.max_pets%TYPE;
    v_max_weight_kg  type_room.max_weight_kg%TYPE;
    v_existing_count NUMBER;
BEGIN
    SELECT tr.max_pets, tr.max_weight_kg
    INTO v_max_pets, v_max_weight_kg
    FROM type_room tr
    JOIN room r ON r.type_room_id = tr.type_room_id
    JOIN booking_room br ON br.room_id = r.room_id
    WHERE br.booking_room_id = :NEW.booking_room_id;

    SELECT COUNT(*)
    INTO v_existing_count
    FROM booking_room_pet brp
    WHERE brp.booking_room_id = p_booking_room_id;

    IF v_existing_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20051,
            'Room is not empty. This procedure only applies to empty rooms.');
    END IF;

    IF p_pet_count > v_max_pets THEN
        RAISE_APPLICATION_ERROR(
            -20053,
            'The number of pets exceeds the room capacity. Max pets allowed = ' ||v_max_pets
        );
    END IF;

    IF v_max_weight_kg IS NOT NULL
       AND p_max_pet_weight IS NOT NULL
       AND p_max_pet_weight > v_max_weight_kg THEN
        RAISE_APPLICATION_ERROR(
            -20055,
            'One or more pets exceed the room weight limit. Max weight allowed = ' ||v_max_weight_kg||' kg'
        );
    END IF;
END;
/
