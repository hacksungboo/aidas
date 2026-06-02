#/home/user1/aidas/services/web/models.py
from sqlalchemy import Column, Integer, String
from app.db import Base

class Product(Base):
    __tablename__ = "products"

    product_id = Column(Integer, primary_key=True, index=True)
    product_name = Column(String, nullable=False)
    price = Column(Integer, nullable=False)
    stock_quantity = Column(Integer, nullable=False)