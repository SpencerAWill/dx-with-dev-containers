using System.Text.Json;
using Azure.Storage.Blobs;
using Data;
using Data.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Worker.Services;

namespace Worker.Functions;

public class ClassifyImageFunction(
    ImageClassifier classifier,
    BlobServiceClient blobService,
    AppDbContext db,
    ILogger<ClassifyImageFunction> logger)
{
    private record ImageUploadedMessage(Guid ImageId, string BlobUri);

    [Function(nameof(ClassifyImage))]
    public async Task ClassifyImage(
        [ServiceBusTrigger("image-processing", Connection = "ConnectionStrings:ServiceBus")]
        string messageBody)
    {
        var message = JsonSerializer.Deserialize<ImageUploadedMessage>(messageBody,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;

        logger.LogInformation("Processing image {ImageId}", message.ImageId);

        var image = await db.Images.FindAsync(message.ImageId);
        if (image is null)
        {
            logger.LogWarning("Image {ImageId} not found in database", message.ImageId);
            return;
        }

        image.Status = ImageStatus.Processing;
        await db.SaveChangesAsync();

        try
        {
            var container = blobService.GetBlobContainerClient("images");
            var blobName = new Uri(message.BlobUri).Segments[^1];
            var blobClient = container.GetBlobClient(blobName);

            using var blobStream = new MemoryStream();
            await blobClient.DownloadToAsync(blobStream);
            blobStream.Position = 0;

            var result = classifier.Classify(blobStream);

            image.ClassificationLabel = result.Label;
            image.Confidence = result.Confidence;
            image.Status = ImageStatus.Classified;
            image.ClassifiedAt = DateTime.UtcNow;

            logger.LogInformation("Image {ImageId} classified as {Label} ({Confidence:P1})",
                message.ImageId, result.Label, result.Confidence);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to classify image {ImageId}", message.ImageId);
            image.Status = ImageStatus.Failed;
        }

        await db.SaveChangesAsync();
    }
}
