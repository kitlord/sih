from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import Apiary, BatchEvent, Hive, HoneyBatch, Package, QualityCheck, Review, User

# These registrations are a dev/debugging aid (eyeball what a migration or a
# GraphQL mutation actually wrote) -- they are NOT the product's Admin-role
# UI, which is the separate Flutter admin dashboard.


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    fieldsets = DjangoUserAdmin.fieldsets + (("Honey Chain", {"fields": ("role",)}),)
    list_display = ("username", "email", "role", "is_staff", "is_active")
    list_filter = ("role", "is_staff", "is_active")


@admin.register(Apiary)
class ApiaryAdmin(admin.ModelAdmin):
    list_display = ("name", "owner", "location_description", "created_at")
    list_filter = ("owner",)
    search_fields = ("name", "location_description")


@admin.register(Hive)
class HiveAdmin(admin.ModelAdmin):
    list_display = ("label", "apiary", "hive_type", "is_active", "created_at")
    list_filter = ("apiary", "is_active")
    search_fields = ("label",)


class BatchEventInline(admin.TabularInline):
    model = BatchEvent
    extra = 0
    readonly_fields = (
        "event_type",
        "actor",
        "timestamp",
        "event_data",
        "data_hash",
        "tx_hash",
        "block_number",
        "chain_event_index",
        "chain_status",
    )
    can_delete = False


@admin.register(HoneyBatch)
class HoneyBatchAdmin(admin.ModelAdmin):
    list_display = ("batch_id", "apiary", "beekeeper", "status", "harvest_date", "quantity_kg", "created_at")
    list_filter = ("status", "apiary")
    search_fields = ("batch_id", "floral_source")
    filter_horizontal = ("hives",)
    inlines = [BatchEventInline]


@admin.register(BatchEvent)
class BatchEventAdmin(admin.ModelAdmin):
    list_display = ("batch", "event_type", "actor", "timestamp", "chain_status", "tx_hash")
    list_filter = ("event_type", "chain_status")
    search_fields = ("batch__batch_id", "tx_hash", "data_hash")


@admin.register(QualityCheck)
class QualityCheckAdmin(admin.ModelAdmin):
    list_display = ("batch", "reviewed_by", "result", "moisture_content", "checked_at")
    list_filter = ("result",)


@admin.register(Package)
class PackageAdmin(admin.ModelAdmin):
    list_display = ("package_code", "review_code", "batch", "unit_count", "packaged_by", "packaged_at")
    search_fields = ("package_code", "review_code", "batch__batch_id")
    readonly_fields = ("review_code",)


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ("batch", "rating", "reviewer_name", "submitted_at")
    list_filter = ("rating",)
    search_fields = ("batch__batch_id", "reviewer_name", "comment")
