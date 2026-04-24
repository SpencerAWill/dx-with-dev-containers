using Data.Models;

namespace Unit.Tests;

public class ImageModelTests
{
    [Fact]
    public void New_image_has_uploaded_status()
    {
        var image = new Image
        {
            OriginalFileName = "cat.jpg",
            ContentType = "image/jpeg",
            BlobUri = "http://azurite:10000/devstoreaccount1/images/cat.jpg"
        };

        Assert.Equal(ImageStatus.Uploaded, image.Status);
    }

    [Fact]
    public void New_image_has_generated_id()
    {
        var image = new Image
        {
            OriginalFileName = "cat.jpg",
            ContentType = "image/jpeg",
            BlobUri = "http://azurite:10000/devstoreaccount1/images/cat.jpg"
        };

        Assert.NotEqual(Guid.Empty, image.Id);
    }

    [Fact]
    public void New_image_has_null_classification_fields()
    {
        var image = new Image
        {
            OriginalFileName = "cat.jpg",
            ContentType = "image/jpeg",
            BlobUri = "http://azurite:10000/devstoreaccount1/images/cat.jpg"
        };

        Assert.Null(image.ClassificationLabel);
        Assert.Null(image.Confidence);
        Assert.Null(image.ClassifiedAt);
    }
}
