from io import BytesIO

import qrcode
from django.core.files.base import ContentFile


def make_qr_content_file(data: str, filename: str) -> ContentFile:
    """Render `data` (a URL) as a PNG QR code and return it as a Django
    ContentFile ready to assign to an ImageField."""
    img = qrcode.make(data)
    buffer = BytesIO()
    img.save(buffer, format="PNG")
    return ContentFile(buffer.getvalue(), name=filename)
