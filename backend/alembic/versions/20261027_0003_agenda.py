"""meeting agenda

Revision ID: 0003_agenda
Revises: 0002
"""
import sqlalchemy as sa
from alembic import op

revision = "0003_agenda"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("meetings", sa.Column("agenda", sa.JSON(), nullable=True))
    op.add_column("meetings", sa.Column("agenda_ai_suggestion", sa.JSON(), nullable=True))
    op.add_column("meetings", sa.Column("agenda_ai_meta", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("meetings", "agenda_ai_meta")
    op.drop_column("meetings", "agenda_ai_suggestion")
    op.drop_column("meetings", "agenda")
