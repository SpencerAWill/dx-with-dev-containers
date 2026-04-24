using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Data;
using Data.Models;
using Microsoft.EntityFrameworkCore;

namespace WebApi.Endpoints;

public static class ImageEndpoints
{
    private const string ContainerName = "images";
    private const string QueueName = "image-processing";

    public static void MapImageEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/images");

        group.MapGet("/", async (AppDbContext db) =>
        {
            var images = await db.Images
                .OrderByDescending(i => i.UploadedAt)
                .ToListAsync();
            return Results.Ok(images);
        });

        group.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var image = await db.Images.FindAsync(id);
            return image is not null ? Results.Ok(image) : Results.NotFound();
        });

        group.MapPost("/", async (IFormFile file, AppDbContext db, BlobServiceClient blobService, ServiceBusClient serviceBus) =>
        {
            var container = blobService.GetBlobContainerClient(ContainerName);
            await container.CreateIfNotExistsAsync(PublicAccessType.None);

            var blobName = $"{Guid.NewGuid()}{Path.GetExtension(file.FileName)}";
            var blobClient = container.GetBlobClient(blobName);

            await using var stream = file.OpenReadStream();
            await blobClient.UploadAsync(stream, new BlobHttpHeaders { ContentType = file.ContentType });

            var image = new Image
            {
                OriginalFileName = file.FileName,
                ContentType = file.ContentType,
                BlobUri = blobClient.Uri.ToString()
            };

            db.Images.Add(image);
            await db.SaveChangesAsync();

            await using var sender = serviceBus.CreateSender(QueueName);
            var message = new ServiceBusMessage(JsonSerializer.Serialize(new
            {
                imageId = image.Id,
                blobUri = image.BlobUri
            }));
            await sender.SendMessageAsync(message);

            return Results.Created($"/api/images/{image.Id}", image);
        })
        .DisableAntiforgery();

        group.MapGet("/{id:guid}/download", async (Guid id, AppDbContext db, BlobServiceClient blobService) =>
        {
            var image = await db.Images.FindAsync(id);
            if (image is null)
                return Results.NotFound();

            var container = blobService.GetBlobContainerClient(ContainerName);
            var blobName = new Uri(image.BlobUri).Segments[^1];
            var blobClient = container.GetBlobClient(blobName);

            var download = await blobClient.DownloadStreamingAsync();
            return Results.Stream(download.Value.Content, image.ContentType, image.OriginalFileName);
        });

        group.MapDelete("/{id:guid}", async (Guid id, AppDbContext db, BlobServiceClient blobService) =>
        {
            var image = await db.Images.FindAsync(id);
            if (image is null)
                return Results.NotFound();

            var container = blobService.GetBlobContainerClient(ContainerName);
            var blobName = new Uri(image.BlobUri).Segments[^1];
            await container.GetBlobClient(blobName).DeleteIfExistsAsync();

            db.Images.Remove(image);
            await db.SaveChangesAsync();

            return Results.NoContent();
        });
    }
}
