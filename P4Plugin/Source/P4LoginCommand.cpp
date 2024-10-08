#include "P4Command.h"
#include "P4Task.h"
#include "Utility.h"
#include <sstream>

class P4LoginCommand : public P4Command
{
public:
	P4LoginCommand(const char* name) : P4Command(name) { }
	virtual bool Run(P4Task& task, const CommandArgs& args)
	{
		if (!task.IsConnected()) // Cannot login without being connected
		{
			Conn().Log().Info() << "Cannot login when not connected" << Endl;
			return false;
		}

		ClearStatus();

		m_LoggedIn = false;
		m_Password = task.GetP4Password();
		m_CheckingForLoggedIn = args.size() > 1 && (args[1] == "-s");
		bool trustFingerprint = args.size() > 1 && (args[1] == "trust");

		if (trustFingerprint)
			task.CommandRun("trust -y ", this);

		const std::string cmd = std::string("login") + (m_CheckingForLoggedIn ? std::string(" ") + args[1] : std::string());

		if (m_CheckingForLoggedIn)
		{
			task.CommandRunNoLogin(cmd, this);
			// Should not send error to unity when just checking for login status.
		}
		else
		{
			if (!task.CommandRun(cmd, this))
			{
				std::string errorMessage = GetStatusMessage();
				Conn().Log().Fatal() << errorMessage << Endl;
			}
		}

		if (m_CheckingForLoggedIn)
			Conn().Log().Debug() << "Is logged in: " << (m_LoggedIn ? "yes" : "no") << Endl;
		else
			Conn().Log().Info() << "Login " << (m_LoggedIn ? "succeeded" : "failed") << Endl;

		m_CheckingForLoggedIn = false;
		return m_LoggedIn;
	}

	void OutputInfo(char level, const char* data)
	{
		std::string d(data);
		Conn().VerboseLine(d);

		m_LoggedIn = ParseAuthenticationResponse(d);

		if (!m_CheckingForLoggedIn && !m_LoggedIn)
		{
			GetStatus().insert(VCSStatusItem(VCSSEV_Error, d));
		}
	}

	bool ParseAuthenticationResponse(const std::string& responseText)
	{
		if (responseText == "'login' not necessary, no password set for this user.")
		{
			return true;
		}

		if (StartsWith(responseText, "User ") && EndsWith(responseText, " logged in."))
		{
			return true;
		}

		if (StartsWith(responseText, "User ") && responseText.find(" ticket expires in ") != std::string::npos)
		{
			return true;
		}

		// Compatibility with old perforce servers. Sometime authenticate using P4PASSWORD could incur on additional login messages, like:
		// User <username> was authenticated by password not ticket.
		// This message is acceptable.
		// ref: https://kb.perforce.com/UserTasks/ConfiguringP4/AvoidingTheP..rdInWindows
		if (StartsWith(responseText, "User ") && EndsWith(responseText, " was authenticated by password not ticket."))
		{
			return true;
		}

		// When the Perforce license is about to expire, the server returns a warning message as part of the login response
		// E.g. Your license is due to expire on 2024/02/26; please contact sales@perforce.com to obtain an updated license file to avoid downtime. User xyz logged in.
		if (StartsWith(responseText, "Your license is due to expire on ") && EndsWith(responseText, " logged in."))
		{
			return true;
		}

		return false;
	}

	// Default handler of P4 error output. Called by the default P4Command::Message() handler.
	void HandleError(Error* err)
	{
		if (err == 0)
			return;

		StrBuf buf;
		err->Fmt(&buf);
		std::string value(buf.Text());

		if (value.find("Unicode server permits only unicode enabled clients") != std::string::npos ||
			value.find("The authenticity of") != std::string::npos)
		{
			VCSStatus s = errorToVCSStatus(*err);
			GetStatus().insert(s.begin(), s.end());
			return; // Do not propagate. It will be handled by P4Task and is not an error. 
		}

		// Suppress errors when just checking for logged in state
		if (m_CheckingForLoggedIn)
			return;

		// Base implementation. Will callback to P4Command::OutputError 
		P4Command::HandleError(err);
	}

	// Entering password
	void Prompt(const StrPtr& msg, StrBuf& buf, int noEcho, Error* e)
	{
		Conn().Log().Info() << "Prompted for password by server" << Endl;
		Conn().Log().Debug() << "Prompt: " << msg.Text() << Endl;
		buf.Set(m_Password.c_str());
		Conn().VerboseLine("Prompted for password");
	}

private:
	bool m_LoggedIn;
	std::string m_Password;
	bool m_CheckingForLoggedIn;

} cLogin("login");
