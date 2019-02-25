
-- TRIGGER KIỂM TRA TÍNH HỢP LỆ SỐ LƯỢNG CỦA SẢN PHẨM

DROP TRIGGER IF EXISTS `QUANTITY_ORDER_VALIDATION`;
DELIMITER $$
CREATE TRIGGER `QUANTITY_ORDER_VALIDATION`
BEFORE INSERT ON `ORDER_DETAILS`
FOR EACH ROW
BEGIN 
	IF (NEW.QUANTITY <= 0 OR NEW.QUANTITY > (
		SELECT PRODUCTS.QUANTITY FROM PRODUCTS 
		WHERE NEW.PROD_ID = PRODUCTS.PROD_ID)) 
    THEN 
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'THE QUANTITY IS REQUIRED AND MUST BE SMALLER THAN THE QUANTITY IN THE PRODUCTS TABLE.';
	END IF;
END$$
DELIMITER ;

INSERT INTO `ORDERS` (CUS_ID,EMP_ID,DATE_SOLD) 
	VALUE(3,6,'2018/12/04');
    
INSERT INTO `ORDER_DETAILS` (ORD_ID,PROD_ID,QUANTITY) 
	VALUE(15,1,0);

-- TRIGGER KIỂM TRA TÍNH HỢP LỆ GIÁ BÁN CỦA SẢN PHẨM

DROP TRIGGER IF EXISTS `PRICE_FOR_SALE_VALIDATION`;
DELIMITER $$
CREATE TRIGGER `PRICE_FOR_SALE_VALIDATION`
BEFORE INSERT ON `PRODUCTS`
FOR EACH ROW
BEGIN 
	IF (NEW.PRICE_IMPORT > NEW.PRICE_SALE OR NEW.PRICE_SALE <= 0)
    THEN 
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'THE PRICES ARE REQUIRED AND THE PRICE_SALE MUST BE MORE THAN PRICE_IMPORT.';
	END IF;
END$$
DELIMITER ;



-- TRIGGER THEO DÕI VÀ CẬP NHẬT LẠI SỐ LƯỢNG SẢN PHẨM SAU KHI BÁN

DROP TRIGGER IF EXISTS `UPDATE_QUANTITY_AFTER_ORDERING`;
DELIMITER $$
CREATE TRIGGER `UPDATE_QUANTITY_AFTER_ORDERING`
BEFORE INSERT ON `ORDER_DETAILS`
FOR EACH ROW
FOLLOWS `QUANTITY_ORDER_VALIDATION`
BEGIN 
	DECLARE OLD_QUANTITY INT;
    DECLARE NEW_QUANTITY INT;
    
    SELECT QUANTITY INTO OLD_QUANTITY FROM PRODUCTS
	WHERE PROD_ID = NEW.PROD_ID;
    
	UPDATE PRODUCTS
    SET QUANTITY = QUANTITY - NEW.QUANTITY 
    WHERE PRODUCTS.PROD_ID = NEW.PROD_ID;
    
    SELECT QUANTITY INTO NEW_QUANTITY FROM PRODUCTS
	WHERE PROD_ID = NEW.PROD_ID;
    
    IF NEW.QUANTITY != OLD_QUANTITY THEN    
		INSERT INTO PRODUCTS_AUDIT (PROD_ID,MESSAGE)
		VALUE (NEW.PROD_ID,CONCAT('THE QUANTITY OF THIS PRODUCT WAS CHANGED FROM ',OLD_QUANTITY,' TO ', NEW_QUANTITY, ' AFTER ORDERING.'));
	END IF;
END$$
DELIMITER ;

-- TRIGGER KIỂM TRA VÀ CẬP NHẬT LẠI SỐ LƯỢNG TRONG KHO SAU KHI NHẬP HÀNG

DROP TRIGGER IF EXISTS `UPDATE_QUANTITY_AFTER_IMPORTING`;
DELIMITER $$
CREATE TRIGGER `UPDATE_QUANTITY_AFTER_IMPORTING` 
BEFORE INSERT ON `IMPORT_DETAILS`
FOR EACH ROW
BEGIN
	DECLARE INVENTORY INT;
    DECLARE NEW_QUANTITY INT;
    
    SELECT QUANTITY INTO INVENTORY FROM PRODUCTS
    WHERE PROD_ID = NEW.PROD_ID;
    
	UPDATE PRODUCTS
	SET QUANTITY = QUANTITY + NEW.QUANTITY 
	WHERE PRODUCTS.PROD_ID = NEW.PROD_ID;
            
	SELECT QUANTITY INTO NEW_QUANTITY FROM PRODUCTS
	WHERE PROD_ID = NEW.PROD_ID;
    
	IF NEW.QUANTITY != INVENTORY THEN    
		INSERT INTO PRODUCTS_AUDIT (PROD_ID,MESSAGE) VALUE 
		(NEW.PROD_ID,CONCAT('THE QUANTITY OF THIS PRODUCT WAS CHANGED FROM ',INVENTORY,' TO ',NEW_QUANTITY,' AFTER IMPORTING.'));
	END IF;
END$$
DELIMITER ;


-- FUNCTION TÍNH ĐƠN HÀNG CÓ KHUYẾN MÃI HOẶC KHÔNG CÓ KHUYÊN MÃI
/*
	INPUT_ID : ID CỦA HÓA ĐƠN.
    PERCENT : GIẢM GIÁ BAO NHIÊU %. 
    LƯU Ý: NẾU KHÔNG CÓ KHUẾN MÃI THÌ NHẬP PERCENT = 0.
*/
DROP FUNCTION IF EXISTS `CALC_SALE_OFF_ORDER`;
DELIMITER $$
CREATE FUNCTION `CALC_SALE_OFF_ORDER` (INPUT_ID INT(11),PERCENT INT) RETURNS INT DETERMINISTIC
BEGIN	
    DECLARE NO_MORE_ORDERS,ORD_PRICE,TOTAL_PRICE INT(11) DEFAULT 0;
   
	DECLARE ORD_PRODUCTS CURSOR FOR 
	SELECT ORDER_DETAILS.QUANTITY * PRODUCTS.PRICE_SALE
	FROM PRODUCTS JOIN ORDER_DETAILS ON PRODUCTS.PROD_ID = ORDER_DETAILS.PROD_ID 
	WHERE ORDER_DETAILS.ORD_ID = INPUT_ID; 
   
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET NO_MORE_ORDERS =1;
    
	SET TOTAL_PRICE = 0;
	OPEN ORD_PRODUCTS;
	FETCH ORD_PRODUCTS INTO ORD_PRICE;
   
	WHILE NO_MORE_ORDERS != 1 DO 
		BEGIN
			SET TOTAL_PRICE = TOTAL_PRICE + ORD_PRICE;
			FETCH ORD_PRODUCTS INTO ORD_PRICE;
		END;
	END WHILE;
	CLOSE ORD_PRODUCTS;
    
	RETURN TOTAL_PRICE * ((100 - PERCENT)/100);
END$$
DELIMITER ;

-- TÌM KHÁCH HÀNG CÓ SỐ LẦN ORDER LÀ BAO NHIÊU ĐÓ VÀ TIẾN HÀNH GIẢM GIÁ
/*
	- NHẬP: 
		ORDER_ID  : HÓA ĐƠN CỦA KHÁCH HÀNG ĐƯỢC GIẢM GIÁ.
        MEMBER_ID : ID CỦA KHÁCH HÀNG CẦN ĐUOẸC GIẢM GIÁ.
        QUANTITY_TO_SALE : SỐ LƯỢNG ORDER TỪ TRƯỚC GIỜ LÀ BAO NHIÊU NHIÊU THÌ MỚI ĐƯỢC SALE OFF.
*/ 
DROP PROCEDURE IF EXISTS `SALE_OFF_LOYAL_CUSTOMER`;
DELIMITER $$
CREATE PROCEDURE `SALE_OFF_LOYAL_CUSTOMER`
(IN ORDER_ID INT(11),IN MEMBER_ID INT,IN QUANTITY_TO_SALE INT)
BEGIN
	DECLARE ORD_QUANTITY INT;
    
    SELECT COUNT(ORD_ID) INTO ORD_QUANTITY FROM ORDERS
    WHERE MEMBER_ID = CUS_ID;
    
    IF ORD_QUANTITY > QUANTITY_TO_SALE THEN
		SELECT CALC_SALE_OFF_ORDER(ORDER_ID,20) AS TOTAL_SALE_OFF_BILL;
	ELSEIF ORD_QUANTITY = QUANTITY_TO_SALE THEN
		SELECT CALC_SALE_OFF_ORDER(ORDER_ID,15) AS TOTAL_SALE_OFF_BILL;
	END IF;
END$$
DELIMITER ;

CALL SALE_OFF_LOYAL_CUSTOMER(2,2,4);



-- PROCEDURE THAY ĐỔI GIÁ TRỊ P_STATUS CỦA SẢN PHẨM

DROP PROCEDURE IF EXISTS `SET_PRODUCT_STATUS`;
DELIMITER $$
CREATE PROCEDURE `SET_PRODUCT_STATUS`(IN PRODUCT_ID INT) 
BEGIN 
	DECLARE PRD_QUANTITY INT;
    SELECT QUANTITY INTO PRD_QUANTITY FROM PRODUCTS
    WHERE PRODUCTS.PROD_ID = PRODUCT_ID;

	IF PRD_QUANTITY >= 100 THEN
		UPDATE PRODUCTS SET P_STATUS = 'CÒN HÀNG'
		WHERE PRODUCTS.PROD_ID = PRODUCT_ID AND PRODUCTS.QUANTITY >= 100;
	ELSEIF PRD_QUANTITY > 0 AND PRD_QUANTITY < 50 THEN
		UPDATE PRODUCTS SET P_STATUS = 'SẮP HẾT HÀNG'
		WHERE PRODUCTS.PROD_ID = PRODUCT_ID AND PRODUCTS.QUANTITY > 0 AND PRODUCTS.QUANTITY <= 50;
	END IF;
END$$
DELIMITER ;

CALL SET_PRODUCT_STATUS(2);

/*-------------------------------------------------------------------------------------------*/
-- FUNCTION TÍNH LỢI NHUẬN HÀNG THÁNG VÀ THÁNG ĐƯỢC TRUYỀN VÀO HỔ TRỢ CHO EVENT
DELIMITER $$
	DROP FUNCTION IF EXISTS  GETSTATISTICS $$
	CREATE FUNCTION  GETSTATISTICS(DATE DATETIME) RETURNS INT DETERMINISTIC 
		BEGIN
			 DECLARE PROFIT INT DEFAULT 0;
			 DECLARE REVENUE INT DEFAULT 0;
			 DECLARE COST INT DEFAULT 0;
			 
			 SET REVENUE=(SELECT SUM(ORDD.QUANTITY * PROD.PRICE_SALE)
				 FROM PRODUCTS AS PROD,ORDER_DETAILS AS ORDD,ORDERS AS ORD
				 WHERE PROD.PROD_ID=ORDD.PROD_ID
				 AND ORD.ORD_ID=ORDD.ORD_ID
				 AND  MONTH (ORD.DATE_SALE) =MONTH(DATE));
				 
			 SET REVENUE=(SELECT SUM(ORDD.QUANTITY * PROD.PRICE_IMPORT)
				 FROM PRODUCTS AS PROD,ORDER_DETAILS AS ORDD,ORDERS AS ORD 
				 WHERE PROD.PROD_ID=ORDD.PROD_ID
				 AND ORD.ORD_ID=ORDD.ORD_ID
				 AND  MONTH (ORD.DATE_SALE) =MONTH(DATE));
				 
			 SET PROFIT=REVENUE-COST;
			 RETURN PROFIT;
		END $$
DELIMITER ;

/*----------------------------------------------------------------------------------------------------------------*/
-- FUNCTION TÍNH GIẢM GIÁ 20% . ĐỂ HỔ TRỢ CHO EVENT SALE 
DELIMITER $$
	DROP FUNCTION IF EXISTS  GETPRICESALE $$
	CREATE FUNCTION  GETPRICESALE() RETURNS INT DETERMINISTIC 
		BEGIN
			 DECLARE SUMS INT DEFAULT 0;
			 SET SUMS = (SELECT (SUM(ORDD.QUANTITY * PROD.PRICE_SALE))/100*80 
			 FROM PRODUCTS AS PROD,  ORDER_DETAILS AS ORDD
			 WHERE PROD.PROD_ID=ORDD.PROD_ID);
			 RETURN SUMS;
		END $$
	DELIMITER ;
	
    SELECT GETPRICESALE();
    
/*--------------------------------------------------EVENT------------------------------------------------------------*/
-- EVENT TÍNH LỢI NHUẬN TỪNG THÁNG GỌI TỪ FUCTION TÍNH LỢI NHUÂN . SẼ CHẠY VÀO NGÀY 30 HÀNG THÁNG ĐỂ TÍNH HẾT LỢI NHUẬN TRONG THÁNG ĐÓ
    DROP EVENT IF EXISTS EVENT_STATISTICS_SHOP;
	CREATE EVENT EVENT_STATISTICS_SHOP
    ON SCHEDULE EVERY 1 MONTH
	STARTS TIMESTAMP('2018-12-30 08:00:00')
	ENDS TIMESTAMP('2019-12-30 08:00:00')
	ON COMPLETION PRESERVE
	ENABLE
	DO INSERT INTO MESSAGES(CONTENT, CREATED_DATE)
	VALUES (CONCAT( 'PROFIT IN THE MONTH IS:',GETSTATISTICS(CURRENT_TIMESTAMP())), CURRENT_TIMESTAMP());

  
    /*---------------------------------------------------------------------------------------------------*/
    -- EVENT GIẢM GIÁ VÀO NGÀY SINH NHẬT CỬA HÀNG HÀNG NĂM 
    DROP EVENT IF EXISTS EVENT_SALE;
	CREATE EVENT EVENT_SALE
	ON SCHEDULE EVERY 1 YEAR
	STARTS TIMESTAMP('2019-02-14 08:00:00')
	ENDS TIMESTAMP('2024-02-14 08:00:00')
	ON COMPLETION PRESERVE
	ENABLE
	DO INSERT INTO MESSAGES(CONTENT, CREATED_DATE)
	VALUES (CONCAT('YOU ARE ENTITLED TO A 20% DISCOUNT',GETPRICESALE()), NOW());
    
    
    SHOW EVENTS FROM SPORT_SHOP; -- SHOW EVNT CỦA HỆ THỐNG
    SELECT * FROM MESSAGES; -- THÔNG TIN SẼ EVENT CHẠY SẼ ĐƯỢC LƯU TRONG BẢNG NÀY
    

-- THÔNG KÊ SẢN PHẨM SẢN PHẨM NÀO <=5 ĐỂ NHẬP HÀNG
    DROP VIEW IF EXISTS OVER_NOTIFICATION_PRODUCTS;
	CREATE VIEW OVER_NOTIFICATION_PRODUCTS AS
    SELECT PROD.PROD_NAME,PROD.QUANTITY,PROD.STATUS,PUB.PUB_NAME
    FROM PRODUCTS AS PROD, PUBLISHERS AS PUB 
    WHERE PROD.PUB_ID=PUB.ID
    AND PROD.QUANTITY<=5;
	
    SELECT * FROM OVER_NOTIFICATION_PRODUCTS;

   
-- TÍNH  ĐƯỢC LỢI NHUẬN BÁN HÀNG CỦA TỪNG NHÂN  VIÊN 
	DROP VIEW IF EXISTS EMPLOYEES_OF_PROFIT;
	CREATE VIEW EMPLOYEES_OF_PROFIT AS
		SELECT 
			ORD.DATE_SALE AS NGAY_BAN_HANG,
			EMP.EMP_NAME AS TEN_NHAN_VIEN_BAN_HANG,
			(ORDD.QUANTITY * PROD.PRICE_SALE) AS TIEN_BAN,
			(ORDD.QUANTITY * PROD.PRICE_IMPORT) AS TIEN_NHAP,
			((ORDD.QUANTITY * PROD.PRICE_SALE) - (ORDD.QUANTITY * PROD.PRICE_IMPORT)) AS LOI_NHUAN
		FROM
			ORDER_DETAILS AS ORDD,
			EMPLOYEES AS EMP,
			ORDERS AS ORD,
			PRODUCTS AS PROD
		WHERE
			ORD.EMP_ID = EMP.EMP_ID
				AND ORDD.ORD_ID = ORD.ORD_ID
				AND ORDD.PROD_ID = PROD.PROD_ID
				GROUP BY ORD.DATE_SALE;
	SELECT *FROM EMPLOYEES_OF_PROFIT;
  
-- FULLTEXT TÌM KIẾM SẢN PHẨM 
ALTER TABLE PRODUCTS ADD FULLTEXT(PROD_NAME);
SELECT * FROM PRODUCTS WHERE MATCH (PROD_NAME) AGAINST ('QUAN AO THE THAO TRE EM' IN NATURAL LANGUAGE MODE);
SHOW EVENTS FROM SPORT_SHOP;
    
-- FULLTEXT TÌM RA NHỮNG SẢN PHẨM BÁN CHẠY ĐỂ TRƯNG BÀY CHÍNH TRONG CỬA HÀNG
ALTER TABLE PRODUCTS ADD FULLTEXT(P_STATUS);
SELECT * FROM PRODUCTS WHERE MATCH (P_STATUS) AGAINST ('SẮP HẾT HÀNG' IN NATURAL LANGUAGE MODE);

-- INDEX FULL-TEXT
ALTER TABLE PRODUCTS ADD FULLTEXT(PROD_NAME);
SELECT * FROM PRODUCTS WHERE MATCH (PROD_NAME) AGAINST ('QUAN AO THE THAO TRE EM' IN NATURAL LANGUAGE MODE);

-- INDEX CHO CỘT GIÁ SẢN PHẨM
ALTER TABLE PRODUCTS DROP INDEX PRICE_SALE;
ALTER TABLE PRODUCTS ADD INDEX(PRICE_SALE);

SELECT PROD_NAME,PRICE_IMPORT,PRICE_SALE FROM PRODUCTS;

-- INDEX CHO SỐ LƯỢNG SẢN PHẨM ĐÃ ĐƯỢC ORDER
ALTER TABLE ORDER_DETAILS ADD INDEX(QUANTITY);



INSERT INTO  PRODUCTS(PROD_NAME,SIZE,QUANTITY,PRICE_IMPORT,PRICE_SALE,CATE_ID,PUB_ID)
	VALUE('BỘ QUẦN ÁO THỂ THAO MU TAY NGẮN','M',100,200000,10000,1,1);