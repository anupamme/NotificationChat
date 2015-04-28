//
// Copyright (c) 2015 Related Code - http://relatedcode.com
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <MediaPlayer/MediaPlayer.h>

#import <Parse/Parse.h>
#import "ProgressHUD.h"
#import "IDMPhotoBrowser.h"

#import "AppConstant.h"
#import "camera.h"
#import "common.h"
#import "image.h"
#import "push.h"
#import "recent.h"

#import "ChatView.h"

#import "MMConstants.h"

@interface ChatView ()

@property (nonatomic, assign) MMVoiceTransactionState voiceTransactionState;
@property (nonatomic, strong) MMListener *listener;

@property (nonatomic, strong) MMApp *mindMeldApp;

@property (nonatomic, copy) void (^onTextFieldDidEndEditing)(UITextField *textField);

@end

//-------------------------------------------------------------------------------------------------------------------------------------------------
@interface ChatView()
{
	NSTimer *timer;
	BOOL isLoading;
	BOOL initialized;

	NSString *groupId;

	NSMutableArray *users;
	NSMutableArray *messages;
	NSMutableDictionary *avatars;

	JSQMessagesBubbleImage *bubbleImageOutgoing;
	JSQMessagesBubbleImage *bubbleImageIncoming;
	JSQMessagesAvatarImage *avatarImageBlank;
    
    MMVoiceTransactionState voiceTransactionState;
    MMListener *listener;
    
    MMApp *mindMeldApp;
    
    void (^onTextFieldDidEndEditing)(UITextField *textField);
}
@end
//-------------------------------------------------------------------------------------------------------------------------------------------------

@implementation ChatView

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (id)initWith:(NSString *)groupId_
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	self = [super init];
	groupId = groupId_;
	return self;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewDidLoad
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewDidLoad];
	self.title = @"Chat";
	//---------------------------------------------------------------------------------------------------------------------------------------------
	users = [[NSMutableArray alloc] init];
	messages = [[NSMutableArray alloc] init];
	avatars = [[NSMutableDictionary alloc] init];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	PFUser *user = [PFUser currentUser];
	self.senderId = user.objectId;
	self.senderDisplayName = user[PF_USER_FULLNAME];
    printf("name, id: %s %s", [self.senderDisplayName UTF8String], [self.senderId UTF8String]);
	//---------------------------------------------------------------------------------------------------------------------------------------------
	JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
	bubbleImageOutgoing = [bubbleFactory outgoingMessagesBubbleImageWithColor:COLOR_OUTGOING];
	bubbleImageIncoming = [bubbleFactory incomingMessagesBubbleImageWithColor:COLOR_INCOMING];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	avatarImageBlank = [JSQMessagesAvatarImageFactory avatarImageWithImage:[UIImage imageNamed:@"chat_blank2"] diameter:30.0];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	isLoading = NO;
	initialized = NO;
	[self loadMessages];
    
//    [self startMindMeld];
//    [self createListener];
}

/**
 *  (1)
 *  To set up the MindMeld SDK we create an MMApp using our application ID and call start.
 */
- (void)startMindMeld {
    self.mindMeldApp = [[MMApp alloc] initWithAppID:kMindMeldAppID];
    typeof(self) __weak weakSelf = self;
    [self.mindMeldApp start:nil
                  onSuccess:^(id ignored) {
                      /**
                       *  (2)
                       *  Now that the SDK has been initialized, we'll set the delegate and
                       *  subscribe to updates to the documents list.
                       */
                      weakSelf.mindMeldApp.delegate = weakSelf;
                      weakSelf.mindMeldApp.activeSession.documents.useBothPushAndPull = NO;
                      [weakSelf.mindMeldApp.activeSession.documents startUpdates];
                  }
                  onFailure:nil];
}

/**
 *  Here we create a listener and set its configuration and callbacks.
 */
- (void)createListener {
    self.listener = [MMListener listener];
    self.listener.continuous = YES; // continuous speech recognition
    self.listener.interimResults = YES;
    
    /**
     *  (4)
     *  In onBeganRecording, onFinishedRecording, onFinished and onVolumeChanged we are just changing
     *  the state so we can update the UI.
     */
    typeof(self) __weak weakSelf = self;
    self.listener.onBeganRecording = ^(MMListener *listener) {
        NSLog(@"listener began recording:" );
        weakSelf.voiceTransactionState = MMVoiceTransactionStateRecording;
    };
    
    self.listener.onFinishedRecording = ^(MMListener *listener) {
        NSLog(@"listener finished recording:");
        weakSelf.voiceTransactionState = MMVoiceTransactionStateProcessing;
    };
    
    self.listener.onFinished = ^(MMListener *listener) {
        NSLog(@"listener finished:");
        weakSelf.voiceTransactionState = MMVoiceTransactionStateIdle;
    };
    
//    self.listener.onVolumeChanged = ^(MMListener *listener, Float32 avgVolumeLevel, Float32 peakVolumeLevel) {
//        weakSelf.speakButton.volumeLevel = avgVolumeLevel;
//    };
    
    /**
     *  (5)
     *  After recording and processing the user's speech, we'll receive the parsed text from the listener.
     *  We need to add a text entry so that we can get related documents.
     */
    self.listener.onResult = ^(MMListener *listener, MMListenerResult *newResult) {
        if (newResult.transcript.length) {
            // use different text colors to indicate interim and final results
            NSDictionary *finalStringAttributes = @{ NSForegroundColorAttributeName: [UIColor blackColor] };
            NSDictionary *interimStringAttributes = @{ NSForegroundColorAttributeName: [UIColor darkGrayColor] };
            NSMutableAttributedString *text = [NSMutableAttributedString new];
            for (MMListenerResult *result in listener.results) {
                NSDictionary *textAttributes = result.final ? finalStringAttributes : interimStringAttributes;
                NSAttributedString *textSegment = [[NSAttributedString alloc] initWithString:result.transcript
                                                                                  attributes:textAttributes];
                [text appendAttributedString:textSegment];
                if (result.final){
                    const char *tmp = [[text string] UTF8String];
                    //printf("####: %s", tmp);
                    [self sendBotMessageChar: tmp];
                }
            }
     //       weakSelf.label.attributedText = text;
            
            
//            if (newResult.final) {
//                [weakSelf addMindMeldTextEntry:weakSelf.label.text];
//            }
        }
    };
    
    // Here we handle any errors that may be ocurring
    self.listener.onError = ^(MMListener *listener, NSError *error) {
        NSLog(@"listener error: %@", error);
        weakSelf.voiceTransactionState = MMVoiceTransactionStateIdle;
//        [UIAlertView showErrorAlert:error.localizedDescription];
    };
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewDidAppear:animated];
	self.collectionView.collectionViewLayout.springinessEnabled = YES;
	timer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(loadMessages) userInfo:nil repeats:YES];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewWillDisappear:(BOOL)animated
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewWillDisappear:animated];
	ClearRecentCounter(groupId);
	[timer invalidate];
}

#pragma mark - Backend methods

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)loadMessagesOld
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if (isLoading == NO)
	{
		isLoading = YES;
		JSQMessage *message_last = [messages lastObject];

		PFQuery *query = [PFQuery queryWithClassName:PF_MESSAGE_CLASS_NAME];
		[query whereKey:PF_MESSAGE_GROUPID equalTo:groupId];
		if (message_last != nil) [query whereKey:PF_MESSAGE_CREATEDAT greaterThan:message_last.date];
		[query includeKey:PF_MESSAGE_USER];
		[query orderByDescending:PF_MESSAGE_CREATEDAT];
		[query setLimit:50];
		[query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error)
		{
			if (error == nil)
			{
				BOOL incoming = NO;
				self.automaticallyScrollsToMostRecentMessage = NO;
				for (PFObject *object in [objects reverseObjectEnumerator])
				{
					JSQMessage *message = [self addMessage:object];
                    printf("sender id: %s %s", [[message senderId] UTF8String], [[message senderDisplayName] UTF8String]);
					if ([self incoming:message]) incoming = YES;
				}
				if ([objects count] != 0)
				{
					if (initialized && incoming)
						[JSQSystemSoundPlayer jsq_playMessageReceivedSound];
					[self finishReceivingMessage];
					[self scrollToBottomAnimated:NO];
				}
				self.automaticallyScrollsToMostRecentMessage = YES;
				initialized = YES;
			}
			else [ProgressHUD showError:@"Network error."];
			isLoading = NO;
		}];
	}
}

- (void)loadMessages
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
    if (isLoading == NO)
    {
        isLoading = YES;
        JSQMessage *message;
        NSFileManager *filemgr = [[NSFileManager alloc] init];
        const char *path = [[filemgr currentDirectoryPath] UTF8String];
        printf("current path: %s", path);
        
        JSQPhotoMediaItem *mediaItem = [[JSQPhotoMediaItem alloc] initWithImage: [[UIImage alloc] initWithContentsOfFile: @"Infinity-Pool"]];
        
        mediaItem.appliesMediaViewMaskAsOutgoing = false;
        message = [[JSQMessage alloc] initWithSenderId:@"ex3aetXvwA" senderDisplayName:@"Gaurang Gupta" date:[[NSDate alloc] init] media:mediaItem];
        //        message = JSQMessage("sksYN48b56", "SUH", NSDate(), mediaItem);
        [messages addObject: message];
        
        // 2. load the text
        [self sendBotMessage: @"So how was your experience at Alila?"];
        self:isLoading = true;
    }
}

- (void) sendBotMessage: (NSString *) text2
{
    JSQMessage *message = [[JSQMessage alloc] initWithSenderId:@"ex3aetXvwA" senderDisplayName:@"Gaurang Gupta" date:[[NSDate alloc] init] text: text2];
    [messages addObject: message];
}

- (void) sendBotMessageChar: (const char *) text2
{
    NSString *input = [[NSString alloc] initWithUTF8String:text2];
    
    JSQMessage *message = [[JSQMessage alloc] initWithSenderId:@"ex3aetXvwA" senderDisplayName:@"Gaurang Gupta" date:[[NSDate alloc] init] text: input];
    [messages addObject: message];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (JSQMessage *)addMessage:(PFObject *)object
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	JSQMessage *message;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	PFUser *user = object[PF_MESSAGE_USER];
	NSString *name = user[PF_USER_FULLNAME];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	PFFile *fileVideo = object[PF_MESSAGE_VIDEO];
	PFFile *filePicture = object[PF_MESSAGE_PICTURE];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if ((filePicture == nil) && (fileVideo == nil))
	{
		message = [[JSQMessage alloc] initWithSenderId:user.objectId senderDisplayName:name date:[[NSDate alloc] init] text:object[PF_MESSAGE_TEXT]];
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if (fileVideo != nil)
	{
		JSQVideoMediaItem *mediaItem = [[JSQVideoMediaItem alloc] initWithFileURL:[NSURL URLWithString:fileVideo.url] isReadyToPlay:YES];
		mediaItem.appliesMediaViewMaskAsOutgoing = [user.objectId isEqualToString:self.senderId];
		message = [[JSQMessage alloc] initWithSenderId:user.objectId senderDisplayName:name date:[[NSDate alloc] init] media:mediaItem];
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if (filePicture != nil)
	{
		JSQPhotoMediaItem *mediaItem = [[JSQPhotoMediaItem alloc] initWithImage:nil];
		mediaItem.appliesMediaViewMaskAsOutgoing = [user.objectId isEqualToString:self.senderId];
		message = [[JSQMessage alloc] initWithSenderId:user.objectId senderDisplayName:name date:[[NSDate alloc] init] media:mediaItem];
		//-----------------------------------------------------------------------------------------------------------------------------------------
		[filePicture getDataInBackgroundWithBlock:^(NSData *imageData, NSError *error)
		{
			if (error == nil)
			{
				mediaItem.image = [UIImage imageWithData:imageData];
				[self.collectionView reloadData];
			}
		}];
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[users addObject:user];
	[messages addObject:message];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	return message;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)loadAvatar:(PFUser *)user
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	PFFile *file = user[PF_USER_THUMBNAIL];
	[file getDataInBackgroundWithBlock:^(NSData *imageData, NSError *error)
	{
		if (error == nil)
		{
			avatars[user.objectId] = [JSQMessagesAvatarImageFactory avatarImageWithImage:[UIImage imageWithData:imageData] diameter:30.0];
			[self.collectionView reloadData];
		}
	}];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)sendMessage:(NSString *)text Video:(NSURL *)video Picture:(UIImage *)picture
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	PFFile *fileVideo = nil;
	PFFile *filePicture = nil;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if (video != nil)
	{
		text = @"[Video message]";
		fileVideo = [PFFile fileWithName:@"video.mp4" data:[[NSFileManager defaultManager] contentsAtPath:video.path]];
		[fileVideo saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error)
		{
			if (error != nil) [ProgressHUD showError:@"Network error."];
		}];
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if (picture != nil)
	{
		text = @"[Picture message]";
		filePicture = [PFFile fileWithName:@"picture.jpg" data:UIImageJPEGRepresentation(picture, 0.6)];
		[filePicture saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error)
		{
			if (error != nil) [ProgressHUD showError:@"Picture save error."];
		}];
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	PFObject *object = [PFObject objectWithClassName:PF_MESSAGE_CLASS_NAME];
	object[PF_MESSAGE_USER] = [PFUser currentUser];
	object[PF_MESSAGE_GROUPID] = groupId;
	object[PF_MESSAGE_TEXT] = text;
	if (fileVideo != nil) object[PF_MESSAGE_VIDEO] = fileVideo;
	if (filePicture != nil) object[PF_MESSAGE_PICTURE] = filePicture;
    [self addMessage: object];
//	[object saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error)
//	{
//		if (error == nil)
//		{
//			[JSQSystemSoundPlayer jsq_playMessageSentSound];
//			[self loadMessages];
//		}
//		else [ProgressHUD showError:@"Network error."];;
//	}];
	//---------------------------------------------------------------------------------------------------------------------------------------------
//	SendPushNotification(groupId, text);
//	UpdateRecentCounter(groupId, 1, text);
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[self finishSendingMessage];
}

#pragma mark - JSQMessagesViewController method overrides

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)didPressSendButton:(UIButton *)button withMessageText:(NSString *)text senderId:(NSString *)senderId senderDisplayName:(NSString *)senderDisplayName date:(NSDate *)date
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[self sendMessage:text Video:nil Picture:nil];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)didPressAccessoryButton:(UIButton *)sender
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	UIActionSheet *action = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
		   otherButtonTitles:@"Take photo or video", @"Choose existing photo", @"Choose existing video", @"Record audio", @"Send location", nil];
	[action showInView:self.view];
}

#pragma mark - JSQMessages CollectionView DataSource

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return messages[indexPath.item];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
			 messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if ([self outgoing:messages[indexPath.item]])
	{
		return bubbleImageOutgoing;
	}
	else return bubbleImageIncoming;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
					avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
    return avatarImageBlank;
//	PFUser *user = users[indexPath.item];
//	if (avatars[user.objectId] == nil)
//	{
//		[self loadAvatar:user];
//		return avatarImageBlank;
//	}
//	else return avatars[user.objectId];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if (indexPath.item % 3 == 0)
	{
		JSQMessage *message = messages[indexPath.item];
		return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:message.date];
	}
	else return nil;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	JSQMessage *message = messages[indexPath.item];
	if ([self incoming:message])
	{
		if (indexPath.item > 0)
		{
			JSQMessage *previous = messages[indexPath.item-1];
			if ([previous.senderId isEqualToString:message.senderId])
			{
				return nil;
			}
		}
		return [[NSAttributedString alloc] initWithString:message.senderDisplayName];
	}
	else return nil;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return nil;
}

#pragma mark - UICollectionView DataSource

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return [messages count];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];

	if ([self outgoing:messages[indexPath.item]])
	{
		cell.textView.textColor = [UIColor whiteColor];
	}
	else
	{
		cell.textView.textColor = [UIColor blackColor];
	}
	return cell;
}

#pragma mark - JSQMessages collection view flow layout delegate

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
				   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if (indexPath.item % 3 == 0)
	{
		return kJSQMessagesCollectionViewCellLabelHeightDefault;
	}
	else return 0;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
				   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	JSQMessage *message = messages[indexPath.item];
	if ([self incoming:message])
	{
		if (indexPath.item > 0)
		{
			JSQMessage *previous = messages[indexPath.item-1];
			if ([previous.senderId isEqualToString:message.senderId])
			{
				return 0;
			}
		}
		return kJSQMessagesCollectionViewCellLabelHeightDefault;
	}
	else return 0;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
				   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return 0;
}

#pragma mark - Responding to collection view tap events

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)collectionView:(JSQMessagesCollectionView *)collectionView
				header:(JSQMessagesLoadEarlierHeaderView *)headerView didTapLoadEarlierMessagesButton:(UIButton *)sender
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	NSLog(@"didTapLoadEarlierMessagesButton");
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapAvatarImageView:(UIImageView *)avatarImageView
		   atIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	NSLog(@"didTapAvatarImageView");
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	JSQMessage *message = messages[indexPath.item];
	if (message.isMediaMessage)
	{
		if ([message.media isKindOfClass:[JSQPhotoMediaItem class]])
		{
			JSQPhotoMediaItem *mediaItem = (JSQPhotoMediaItem *)message.media;
			NSArray *photos = [IDMPhoto photosWithImages:@[mediaItem.image]];
			IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotos:photos];
			[self presentViewController:browser animated:YES completion:nil];
		}
		if ([message.media isKindOfClass:[JSQVideoMediaItem class]])
		{
			JSQVideoMediaItem *mediaItem = (JSQVideoMediaItem *)message.media;
			MPMoviePlayerViewController *moviePlayer = [[MPMoviePlayerViewController alloc] initWithContentURL:mediaItem.fileURL];
			[self presentMoviePlayerViewControllerAnimated:moviePlayer];
			[moviePlayer.moviePlayer play];
		}
	}
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapCellAtIndexPath:(NSIndexPath *)indexPath touchLocation:(CGPoint)touchLocation
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	NSLog(@"didTapCellAtIndexPath %@", NSStringFromCGPoint(touchLocation));
}

#pragma mark - UIActionSheetDelegate

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if (buttonIndex != actionSheet.cancelButtonIndex)
	{
        if (buttonIndex == 0)	{
            [self.listener startListening];
            PresentMultiCamera(self, YES);
            
        }
		if (buttonIndex == 1)	PresentPhotoLibrary(self, YES);
		if (buttonIndex == 2)	PresentVideoLibrary(self, YES);
		if (buttonIndex == 3)	PresentPremium(self);
		if (buttonIndex == 4)	PresentPremium(self);
	}
}

#pragma mark - UIImagePickerControllerDelegate

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	NSURL *video = info[UIImagePickerControllerMediaURL];
	UIImage *picture = info[UIImagePickerControllerEditedImage];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[self sendMessage:nil Video:video Picture:picture];
    [self.listener stopListening];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Helper methods

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (BOOL)incoming:(JSQMessage *)message
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return ([message.senderId isEqualToString:self.senderId] == NO);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (BOOL)outgoing:(JSQMessage *)message
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return ([message.senderId isEqualToString:self.senderId] == YES);
}

@end
