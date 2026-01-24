"""
Unit tests for streaming ZIP extraction.

Tests the memory-efficient stream_extract() method.
"""
import pytest
import zipfile
import tempfile
from pathlib import Path

from app.utils.import_export.zip_handler import ZipHandler


class TestStreamingZip:
    """Test streaming ZIP extraction."""

    @pytest.fixture
    def temp_dir(self):
        """Create temporary directory for tests."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)

    @pytest.fixture
    def sample_zip(self, temp_dir):
        """Create a sample ZIP file for testing."""
        zip_path = temp_dir / "test.zip"

        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            # Add data.json
            zipf.writestr("data.json", '{"journals": [], "version": "1.0"}')

            # Add media files
            zipf.writestr("media/entry1/photo1.jpg", b"fake image data")
            zipf.writestr("media/entry1/photo2.jpg", b"another fake image")
            zipf.writestr("media/entry2/video.mp4", b"fake video data")

        return zip_path

    def test_stream_extract_basic(self, sample_zip, temp_dir):
        """Test basic streaming extraction."""
        extract_to = temp_dir / "extracted"

        result = ZipHandler.stream_extract(
            zip_path=sample_zip,
            extract_to=extract_to,
            max_size_mb=10,
            validate_media=False,  # Disable for basic test
        )

        # Verify result structure
        assert "data_file" in result
        assert "media_dir" in result
        assert "total_size" in result
        assert "file_count" in result

        # Verify data file exists
        assert result["data_file"].exists()
        assert result["data_file"].name == "data.json"

        # Verify file count
        assert result["file_count"] == 4  # data.json + 3 media files

    def test_stream_extract_with_progress(self, sample_zip, temp_dir):
        """Test streaming extraction with progress callback."""
        extract_to = temp_dir / "extracted"
        progress_calls = []

        def track_progress(current, total):
            progress_calls.append((current, total))

        ZipHandler.stream_extract(
            zip_path=sample_zip,
            extract_to=extract_to,
            max_size_mb=10,
            validate_media=False,
            progress_callback=track_progress,
        )

        # Verify progress callback was called
        assert len(progress_calls) == 4  # Once per file
        assert progress_calls[-1] == (4, 4)  # Last call should be (total, total)

    def test_stream_extract_zero_copy_media(self, sample_zip, temp_dir):
        """Test zero-copy media extraction to custom destination."""
        extract_to = temp_dir / "extracted"
        media_dest = temp_dir / "media_storage" / "user123"

        ZipHandler.stream_extract(
            zip_path=sample_zip,
            extract_to=extract_to,
            media_dest=media_dest,
            max_size_mb=10,
            validate_media=False,
        )

        # Verify data.json is in extract_to
        assert (extract_to / "data.json").exists()

        # Verify media files are in media_dest (zero-copy)
        assert (media_dest / "entry1" / "photo1.jpg").exists()
        assert (media_dest / "entry1" / "photo2.jpg").exists()
        assert (media_dest / "entry2" / "video.mp4").exists()

        # Verify media files are NOT in extract_to
        assert not (extract_to / "media").exists()

    def test_stream_extract_size_limit(self, temp_dir):
        """Test size limit enforcement."""
        # Create a ZIP that exceeds limit
        zip_path = temp_dir / "large.zip"

        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            zipf.writestr("data.json", '{"journals": []}')
            # Add large fake file
            large_data = b"x" * (10 * 1024 * 1024)  # 10MB
            zipf.writestr("media/large.jpg", large_data)

        extract_to = temp_dir / "extracted"

        # Should raise ValueError or IOError for exceeding size
        with pytest.raises((ValueError, IOError), match="ZIP too large"):
            ZipHandler.stream_extract(
                zip_path=zip_path,
                extract_to=extract_to,
                max_size_mb=5,  # Limit to 5MB
                validate_media=False,
            )

    def test_stream_extract_path_traversal(self, temp_dir):
        """Test path traversal protection."""
        zip_path = temp_dir / "malicious.zip"

        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            zipf.writestr("data.json", '{"journals": []}')
            # Try to write outside extraction directory
            zipf.writestr("../../../etc/passwd", "malicious content")

        extract_to = temp_dir / "extracted"

        # Should raise ValueError or IOError for unsafe path
        with pytest.raises((ValueError, IOError), match="unsafe path"):
            ZipHandler.stream_extract(
                zip_path=zip_path,
                extract_to=extract_to,
                max_size_mb=10,
                validate_media=False,
            )

    def test_stream_extract_corrupted_zip(self, temp_dir):
        """Test handling of corrupted ZIP file."""
        zip_path = temp_dir / "corrupted.zip"

        # Create corrupted ZIP
        with open(zip_path, 'wb') as f:
            f.write(b"PK\x03\x04" + b"corrupted data")

        extract_to = temp_dir / "extracted"

        # Should raise ValueError or IOError
        with pytest.raises((ValueError, IOError)):
            ZipHandler.stream_extract(
                zip_path=zip_path,
                extract_to=extract_to,
                max_size_mb=10,
                validate_media=False,
            )

    def test_stream_extract_missing_data_file(self, temp_dir):
        """Test handling of ZIP without data.json."""
        zip_path = temp_dir / "no_data.zip"

        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            zipf.writestr("media/photo.jpg", b"image data")

        extract_to = temp_dir / "extracted"

        # Should raise ValueError or IOError for missing data.json
        with pytest.raises((ValueError, IOError), match="Extracted data file not found"):
            ZipHandler.stream_extract(
                zip_path=zip_path,
                extract_to=extract_to,
                max_size_mb=10,
                validate_media=False,
            )
