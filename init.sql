DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    price INTEGER NOT NULL,
    stock_quantity INTEGER NOT NULL
);

INSERT INTO products (product_name, price, stock_quantity) VALUES
('오버핏 하찌 라운드 니트', 39000, 100),
('와이드 생지 데님 팬츠', 45000, 80),
('미니멀 오버핏 셔츠', 34000, 120),
('원턱 테이퍼드 슬랙스', 42000, 90),
('데일리 베이직 후드티', 49000, 150);
