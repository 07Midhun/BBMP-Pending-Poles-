import datetime
from sqlalchemy import (
    Column,
    Integer,
    String,
    Float,
    Boolean,
    DateTime,
    Index,
    JSON,
    Text
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()

class PoleDB(Base):
    __tablename__ = "poles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    pole_number = Column(String(64), unique=True, nullable=False, index=True)
    region = Column(String(64), nullable=False, index=True)
    zone = Column(String(64), nullable=False, index=True)
    ward = Column(String(64), nullable=False, index=True)
    pole_old_lamp = Column(String(32), nullable=True, index=True)
    lamp_type = Column(String(64), nullable=True, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    is_installed = Column(Boolean, default=False, nullable=False, index=True)
    uploaded_slots = Column(JSON, default=list, nullable=False)
    
    # Technician Image URLs (saved on Google Drive)
    image_1_url = Column(Text, nullable=True)
    image_2_url = Column(Text, nullable=True)
    image_3_url = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow, nullable=False)

    __table_args__ = (
        Index("idx_hierarchy", "region", "zone", "ward"),
        Index("idx_filters", "region", "zone", "ward", "pole_old_lamp", "lamp_type", "is_installed"),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "pole_number": self.pole_number,
            "region": self.region,
            "zone": self.zone,
            "ward": self.ward,
            "pole_old_lamp": self.pole_old_lamp or "",
            "lamp_type": self.lamp_type or "",
            "latitude": self.latitude,
            "longitude": self.longitude,
            "is_installed": self.is_installed,
            "uploaded_slots": self.uploaded_slots or [],
            "image_1_url": self.image_1_url or "",
            "image_2_url": self.image_2_url or "",
            "image_3_url": self.image_3_url or "",
        }
